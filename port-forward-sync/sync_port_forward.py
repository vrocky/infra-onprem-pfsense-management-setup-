import argparse
import csv
import ipaddress
import json
import os
import re
import sys
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple

import requests


def load_json_file(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def resolve_path(base_file: Path, raw_path: str) -> Path:
    path = Path(raw_path)
    if path.is_absolute():
        return path
    return (base_file.parent / path).resolve()


def get_nested(data: Any, path: str) -> Any:
    current = data
    if not path:
        return current

    for token in path.split("."):
        if isinstance(current, list):
            if not token.isdigit():
                return None
            index = int(token)
            if index < 0 or index >= len(current):
                return None
            current = current[index]
            continue

        if isinstance(current, dict):
            if token not in current:
                return None
            current = current[token]
            continue

        return None

    return current


def find_ipv4_values(value: Any) -> Set[str]:
    found: Set[str] = set()

    if isinstance(value, dict):
        for sub in value.values():
            found |= find_ipv4_values(sub)
        return found

    if isinstance(value, list):
        for sub in value:
            found |= find_ipv4_values(sub)
        return found

    if isinstance(value, str):
        for candidate in re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", value):
            try:
                parsed = ipaddress.ip_address(candidate)
                if isinstance(parsed, ipaddress.IPv4Address):
                    found.add(str(parsed))
            except ValueError:
                continue

    return found


def ensure_list(data: Any) -> List[Any]:
    if data is None:
        return []
    if isinstance(data, list):
        return data
    return [data]


def substitute_placeholders(value: Any, context: Dict[str, Any]) -> Any:
    if isinstance(value, dict):
        return {k: substitute_placeholders(v, context) for k, v in value.items()}
    if isinstance(value, list):
        return [substitute_placeholders(item, context) for item in value]
    if isinstance(value, str):
        rendered = value
        for key, sub_value in context.items():
            rendered = rendered.replace("{" + key + "}", str(sub_value))
        if re.fullmatch(r"\d+", rendered):
            return int(rendered)
        if rendered.lower() in {"true", "false"}:
            return rendered.lower() == "true"
        return rendered
    return value


def request_json(
    session: requests.Session,
    method: str,
    url: str,
    headers: Dict[str, str],
    verify_tls: bool,
    timeout: int,
    body: Optional[Dict[str, Any]] = None,
    dry_run: bool = False,
) -> Any:
    if dry_run:
        print(f"DRY-RUN {method.upper()} {url}")
        if body is not None:
            print(json.dumps(body, indent=2))
        return None

    response = session.request(
        method=method.upper(),
        url=url,
        headers=headers,
        json=body,
        timeout=timeout,
        verify=verify_tls,
    )
    response.raise_for_status()
    if not response.text.strip():
        return None
    try:
        return response.json()
    except ValueError:
        return {"raw": response.text}


def build_url(base_url: str, endpoint: str) -> str:
    return f"{base_url.rstrip('/')}/{endpoint.lstrip('/')}"


def extract_ip_from_item(
    item: Dict[str, Any],
    ip_fields: List[str],
    interface_field: Optional[str],
    interface_name: Optional[str],
) -> Set[str]:
    if interface_field and interface_name:
        iface = item.get(interface_field)
        if iface is not None and str(iface) != interface_name:
            return set()

    for field in ip_fields:
        if field in item and item[field] is not None:
            return find_ipv4_values(item[field])

    return find_ipv4_values(item)


def discover_active_clients(
    session: requests.Session,
    base_url: str,
    headers: Dict[str, str],
    config: Dict[str, Any],
    dry_run: bool,
) -> Set[str]:
    sources = config["discovery"]["sources"]
    timeout = int(config["api"].get("timeoutSeconds", 20))
    verify_tls = not bool(config["api"].get("skipCertificateCheck", True))
    training_cidr = ipaddress.ip_network(config["mapping"]["trainingSubnetCidr"], strict=False)

    all_clients: Set[str] = set()

    for source in sources:
        method = source.get("method", "GET")
        endpoint = source["endpoint"]
        url = build_url(base_url, endpoint)

        print(f"Discovering clients from {endpoint}")
        response = request_json(
            session=session,
            method=method,
            url=url,
            headers=headers,
            verify_tls=verify_tls,
            timeout=timeout,
            body=source.get("body"),
            dry_run=dry_run,
        )

        if dry_run:
            continue

        search_root = get_nested(response, source.get("responsePath", "")) if response is not None else None
        items = ensure_list(search_root)

        ip_fields = source.get("ipFields", ["ip", "ip_address", "address", "client_ip"])
        interface_field = source.get("interfaceField")
        interface_name = source.get("interfaceName")

        for item in items:
            if isinstance(item, dict):
                candidates = extract_ip_from_item(item, ip_fields, interface_field, interface_name)
            else:
                candidates = find_ipv4_values(item)

            for candidate in candidates:
                if ipaddress.ip_address(candidate) in training_cidr:
                    all_clients.add(candidate)

    return all_clients


def build_desired_mappings(config: Dict[str, Any], active_ips: Iterable[str]) -> List[Dict[str, Any]]:
    mapping = config["mapping"]
    port_base = int(mapping["wanPortBase"])
    target_port = int(mapping.get("targetPort", 3389))
    desc_prefix = str(mapping["descriptionPrefix"])

    desired: List[Dict[str, Any]] = []
    used_ports: Dict[int, str] = {}

    for ip in sorted(active_ips, key=lambda x: tuple(int(o) for o in x.split("."))):
        suffix = int(ip.split(".")[-1])
        wan_port = port_base + suffix

        if wan_port in used_ports:
            raise ValueError(f"Duplicate WAN port computed: {wan_port} for {ip} and {used_ports[wan_port]}")

        used_ports[wan_port] = ip
        vm_name = f"client-{suffix:03d}"

        desired.append(
            {
                "name": vm_name,
                "ip": ip,
                "suffix": suffix,
                "wanPort": wan_port,
                "targetPort": target_port,
                "description": f"{desc_prefix}{vm_name}",
            }
        )

    return desired


def parse_existing_rules(
    response: Any,
    list_path: str,
    description_fields: List[str],
    id_fields: List[str],
) -> Dict[str, Dict[str, Any]]:
    root = get_nested(response, list_path) if list_path else response
    rules = ensure_list(root)

    by_description: Dict[str, Dict[str, Any]] = {}

    for rule in rules:
        if not isinstance(rule, dict):
            continue

        desc = None
        for field in description_fields:
            if field in rule and rule[field] is not None:
                desc = str(rule[field])
                break

        if not desc:
            continue

        rule_id = None
        for field in id_fields:
            if field in rule and rule[field] is not None:
                rule_id = str(rule[field])
                break

        by_description[desc] = {
            "raw": rule,
            "id": rule_id,
        }

    return by_description


def export_mapping_table(output_dir: Path, rows: List[Dict[str, Any]]) -> Tuple[Path, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    csv_path = output_dir / "training-rdp-nat-table.csv"
    md_path = output_dir / "training-rdp-nat-table.md"

    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["name", "ip", "suffix", "wanPort", "targetPort", "description"],
        )
        writer.writeheader()
        writer.writerows(rows)

    lines = [
        "# Training RDP NAT Table",
        "",
        "| Name | IP | Suffix | WAN Port | Target Port | Description |",
        "| --- | --- | ---: | ---: | ---: | --- |",
    ]

    for row in rows:
        lines.append(
            f"| {row['name']} | {row['ip']} | {row['suffix']} | {row['wanPort']} | {row['targetPort']} | {row['description']} |"
        )

    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return csv_path, md_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Idempotent dynamic pfSense RDP NAT sync")
    parser.add_argument("--config", default="config.json", help="Path to config JSON")
    parser.add_argument("--dry-run", action="store_true", help="Print API calls only")
    parser.add_argument("--generate-only", action="store_true", help="Only generate mapping table")
    args = parser.parse_args()

    config_path = Path(args.config).resolve()
    if not config_path.exists():
        print(f"Config not found: {config_path}", file=sys.stderr)
        return 1

    config = load_json_file(config_path)
    base_url = str(config["api"]["baseUrl"]).rstrip("/")
    token_env = str(config["api"]["tokenEnvVar"])
    token = os.getenv(token_env)

    if not token:
        print(f"Environment variable {token_env} is not set.", file=sys.stderr)
        return 1

    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }

    output_dir = resolve_path(config_path, config.get("outputDir", "./generated"))

    session = requests.Session()

    try:
        active_ips = discover_active_clients(
            session=session,
            base_url=base_url,
            headers=headers,
            config=config,
            dry_run=args.dry_run,
        )

        if args.dry_run:
            print("Dry-run mode: discovery calls emitted. Skipping reconciliation.")
            return 0

        desired = build_desired_mappings(config, active_ips)
        csv_path, md_path = export_mapping_table(output_dir, desired)
        print(f"Generated mapping tables: {csv_path} and {md_path}")

        if args.generate_only:
            print("Generate-only mode complete.")
            return 0

        nat = config["nat"]
        timeout = int(config["api"].get("timeoutSeconds", 20))
        verify_tls = not bool(config["api"].get("skipCertificateCheck", True))

        list_url = build_url(base_url, nat["listEndpoint"])
        list_response = request_json(
            session=session,
            method=nat.get("listMethod", "GET"),
            url=list_url,
            headers=headers,
            verify_tls=verify_tls,
            timeout=timeout,
            body=None,
            dry_run=False,
        )

        existing = parse_existing_rules(
            response=list_response,
            list_path=nat.get("listResponsePath", ""),
            description_fields=nat.get("descriptionFields", ["description", "descr"]),
            id_fields=nat.get("idFields", ["id", "uuid", "tracker"]),
        )

        desired_desc = {row["description"] for row in desired}
        created = 0
        skipped = 0

        for row in desired:
            if row["description"] in existing:
                skipped += 1
                continue

            payload_template = deepcopy(nat["createPayloadTemplate"])
            payload = substitute_placeholders(
                payload_template,
                {
                    "description": row["description"],
                    "wan_port": row["wanPort"],
                    "target_ip": row["ip"],
                    "target_port": row["targetPort"],
                    "wan_interface": config["mapping"]["wanInterface"],
                    "protocol": config["mapping"].get("protocol", "tcp"),
                    "destination_address": config["mapping"].get("destinationAddress", "this_firewall"),
                    "associated_rule": config["mapping"].get("associatedRule", "pass"),
                },
            )

            create_url = build_url(base_url, nat["createEndpoint"])
            request_json(
                session=session,
                method=nat.get("createMethod", "POST"),
                url=create_url,
                headers=headers,
                verify_tls=verify_tls,
                timeout=timeout,
                body=payload,
                dry_run=False,
            )
            created += 1

        removed = 0
        if bool(nat.get("removeStaleAutoRules", False)):
            delete_template = nat.get("deleteEndpointTemplate")
            if not delete_template:
                raise ValueError("removeStaleAutoRules=true requires nat.deleteEndpointTemplate")

            prefix = str(config["mapping"]["descriptionPrefix"])
            for desc, item in existing.items():
                if not desc.startswith(prefix):
                    continue
                if desc in desired_desc:
                    continue
                rule_id = item.get("id")
                if not rule_id:
                    print(f"Skipping stale rule without id: {desc}")
                    continue

                delete_endpoint = delete_template.replace("{id}", str(rule_id))
                delete_url = build_url(base_url, delete_endpoint)
                request_json(
                    session=session,
                    method=nat.get("deleteMethod", "DELETE"),
                    url=delete_url,
                    headers=headers,
                    verify_tls=verify_tls,
                    timeout=timeout,
                    body=None,
                    dry_run=False,
                )
                removed += 1

        apply_endpoint = nat.get("applyEndpoint")
        if apply_endpoint:
            apply_url = build_url(base_url, apply_endpoint)
            request_json(
                session=session,
                method=nat.get("applyMethod", "POST"),
                url=apply_url,
                headers=headers,
                verify_tls=verify_tls,
                timeout=timeout,
                body=nat.get("applyBody"),
                dry_run=False,
            )

        print(f"Sync complete. Active clients: {len(desired)}, created: {created}, skipped(existing): {skipped}, removed(stale): {removed}")
        return 0

    except requests.HTTPError as exc:
        print(f"HTTP error: {exc}", file=sys.stderr)
        if exc.response is not None and exc.response.text:
            print(exc.response.text, file=sys.stderr)
        return 2
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 3
    finally:
        session.close()


if __name__ == "__main__":
    sys.exit(main())
