import argparse
import base64
import csv
import ipaddress
import json
import os
import re
import socket
import sys
import time
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple

import requests


def load_json_file(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json_file(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")


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


def ensure_list(data: Any) -> List[Any]:
    if data is None:
        return []
    if isinstance(data, list):
        return data
    return [data]


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


def parse_timestamp(value: Any) -> Optional[float]:
    if value is None:
        return None

    if isinstance(value, (int, float)):
        ts = float(value)
        if ts > 1e12:
            ts = ts / 1000.0
        if ts <= 0:
            return None
        return ts

    if not isinstance(value, str):
        return None

    raw = value.strip()
    if not raw:
        return None

    if re.fullmatch(r"\d{10,13}", raw):
        ts = float(raw)
        if ts > 1e12:
            ts = ts / 1000.0
        return ts

    variants = [
        "%Y-%m-%dT%H:%M:%S%z",
        "%Y-%m-%dT%H:%M:%S.%f%z",
        "%Y-%m-%d %H:%M:%S%z",
        "%Y-%m-%d %H:%M:%S",
    ]

    normalized = raw.replace("Z", "+00:00")
    for fmt in variants:
        try:
            dt = datetime.strptime(normalized, fmt)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.timestamp()
        except ValueError:
            continue

    try:
        dt = datetime.fromisoformat(normalized)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.timestamp()
    except ValueError:
        return None


def substitute_placeholders(value: Any, context: Dict[str, Any]) -> Any:
    if isinstance(value, dict):
        return {k: substitute_placeholders(v, context) for k, v in value.items()}
    if isinstance(value, list):
        return [substitute_placeholders(item, context) for item in value]
    if isinstance(value, str):
        rendered = value
        for key, sub_value in context.items():
            rendered = rendered.replace("{" + key + "}", str(sub_value))
        return rendered
    return value


def build_url(base_url: str, endpoint: str) -> str:
    return f"{base_url.rstrip('/')}/{endpoint.lstrip('/')}"


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


def resolve_api_headers(api_config: Dict[str, Any]) -> Dict[str, str]:
    headers = {"Accept": "application/json"}

    auth_cfg = api_config.get("auth", {})
    mode = str(auth_cfg.get("mode", "token")).strip().lower()

    if mode == "token":
        token_env = str(auth_cfg.get("tokenEnvVar") or api_config.get("tokenEnvVar") or "").strip()
        if not token_env:
            raise ValueError("Token auth selected, but tokenEnvVar is not configured.")
        token = os.getenv(token_env)
        if not token:
            raise ValueError(f"Environment variable {token_env} is not set.")
        headers["Authorization"] = f"Bearer {token}"
        return headers

    if mode == "basic":
        username = str(auth_cfg.get("username", "")).strip()
        password = str(auth_cfg.get("password", "")).strip()

        username_env = str(auth_cfg.get("usernameEnvVar", "")).strip()
        password_env = str(auth_cfg.get("passwordEnvVar", "")).strip()

        if not username and username_env:
            username = str(os.getenv(username_env, "")).strip()
        if not password and password_env:
            password = str(os.getenv(password_env, "")).strip()

        if not username or not password:
            raise ValueError("Basic auth selected, but username/password are missing.")

        raw = f"{username}:{password}".encode("utf-8")
        b64 = base64.b64encode(raw).decode("ascii")
        headers["Authorization"] = f"Basic {b64}"
        return headers

    raise ValueError("api.auth.mode must be one of: token, basic")


def first_present(record: Dict[str, Any], field_names: List[str]) -> Any:
    for field in field_names:
        if field in record and record[field] is not None:
            return record[field]
    return None


def discover_clients(
    session: requests.Session,
    base_url: str,
    headers: Dict[str, str],
    config: Dict[str, Any],
    dry_run: bool,
) -> Dict[str, Dict[str, Any]]:
    training_cidr = ipaddress.ip_network(config["mapping"]["trainingSubnetCidr"], strict=False)
    timeout = int(config["api"].get("timeoutSeconds", 20))
    verify_tls = not bool(config["api"].get("skipCertificateCheck", True))

    sources = config["discovery"]["sources"]
    discovered: Dict[str, Dict[str, Any]] = {}

    for source in sources:
        method = source.get("method", "GET")
        endpoint = source["endpoint"]
        url = build_url(base_url, endpoint)
        print(f"Discovering from source '{source.get('name', endpoint)}' ({endpoint})")

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

        root = get_nested(response, source.get("responsePath", "")) if response is not None else None
        items = ensure_list(root)

        ip_fields = source.get("ipFields", ["ip", "ip_address", "address"])
        interface_field = source.get("interfaceField")
        interface_name = source.get("interfaceName")
        timestamp_fields = source.get("timestampFields", [])
        hostname_fields = source.get("hostnameFields", [])

        for item in items:
            if isinstance(item, dict):
                if interface_field and interface_name:
                    iface = item.get(interface_field)
                    if iface is not None and str(iface) != str(interface_name):
                        continue

                timestamp_value = parse_timestamp(first_present(item, timestamp_fields)) if timestamp_fields else None
                hostname_value = first_present(item, hostname_fields) if hostname_fields else None

                candidates: Set[str] = set()
                for field in ip_fields:
                    if field in item and item[field] is not None:
                        candidates |= find_ipv4_values(item[field])
                if not candidates:
                    candidates = find_ipv4_values(item)
            else:
                timestamp_value = None
                hostname_value = None
                candidates = find_ipv4_values(item)

            for candidate in candidates:
                ip_obj = ipaddress.ip_address(candidate)
                if ip_obj not in training_cidr:
                    continue

                existing = discovered.get(candidate)
                record = {
                    "ip": candidate,
                    "hostname": str(hostname_value) if hostname_value else "",
                    "lastSeenTs": timestamp_value,
                }

                if existing is None:
                    discovered[candidate] = record
                    continue

                current_ts = existing.get("lastSeenTs")
                if current_ts is None and timestamp_value is not None:
                    discovered[candidate] = record
                elif current_ts is not None and timestamp_value is not None and timestamp_value > current_ts:
                    discovered[candidate] = record

    return discovered


def apply_safety_gates(
    discovered: Dict[str, Dict[str, Any]],
    config: Dict[str, Any],
) -> Tuple[List[Dict[str, Any]], Dict[str, int]]:
    safety = config.get("safety", {})
    require_recent = bool(safety.get("requireRecentLease", True))
    min_recent_minutes = int(safety.get("minRecentMinutes", 30))
    allow_unknown = bool(safety.get("allowUnknownLeaseAge", False))
    max_age_seconds = min_recent_minutes * 60
    now = time.time()

    included: List[Dict[str, Any]] = []
    rejected_unknown = 0
    rejected_stale = 0

    for item in discovered.values():
        last_seen = item.get("lastSeenTs")
        if not require_recent:
            included.append(item)
            continue

        if last_seen is None:
            if allow_unknown:
                included.append(item)
            else:
                rejected_unknown += 1
            continue

        age = max(0.0, now - float(last_seen))
        if age <= max_age_seconds:
            included.append(item)
        else:
            rejected_stale += 1

    stats = {
        "discovered": len(discovered),
        "eligible": len(included),
        "rejectedUnknownAge": rejected_unknown,
        "rejectedStale": rejected_stale,
    }
    return included, stats


def can_connect(ip: str, port: int, timeout_ms: int) -> bool:
    timeout_sec = max(0.1, float(timeout_ms) / 1000.0)
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout_sec)
    try:
        sock.connect((ip, int(port)))
        return True
    except OSError:
        return False
    finally:
        sock.close()


def build_desired_mappings(config: Dict[str, Any], clients: Iterable[Dict[str, Any]]) -> List[Dict[str, Any]]:
    mapping = config["mapping"]
    port_base = int(mapping["wanPortBase"])
    target_port = int(mapping.get("targetPort", 3389))
    desc_prefix = str(mapping["descriptionPrefix"])

    desired: List[Dict[str, Any]] = []
    used_ports: Dict[int, str] = {}

    for client in sorted(clients, key=lambda x: tuple(int(o) for o in x["ip"].split("."))):
        ip = str(client["ip"])
        suffix = int(ip.split(".")[-1])
        wan_port = port_base + suffix

        if wan_port in used_ports:
            raise ValueError(f"Duplicate WAN port computed: {wan_port} for {ip} and {used_ports[wan_port]}")
        used_ports[wan_port] = ip

        host = str(client.get("hostname") or "").strip()
        vm_name = host if host else f"client-{suffix:03d}"

        desired.append(
            {
                "name": vm_name,
                "ip": ip,
                "suffix": suffix,
                "wanPort": wan_port,
                "targetPort": target_port,
                "description": f"{desc_prefix}{vm_name}",
                "lastSeenTs": client.get("lastSeenTs"),
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

        by_description[desc] = {"raw": rule, "id": rule_id}

    return by_description


def export_mapping_table(output_dir: Path, rows: List[Dict[str, Any]]) -> Tuple[Path, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    csv_path = output_dir / "training-rdp-nat-table.csv"
    md_path = output_dir / "training-rdp-nat-table.md"

    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["name", "ip", "suffix", "wanPort", "targetPort", "description"],
            extrasaction="ignore",
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


def load_runtime_state(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {"staleFirstSeen": {}}
    data = load_json_file(path)
    if not isinstance(data, dict):
        return {"staleFirstSeen": {}}
    data.setdefault("staleFirstSeen", {})
    if not isinstance(data["staleFirstSeen"], dict):
        data["staleFirstSeen"] = {}
    return data


def main() -> int:
    parser = argparse.ArgumentParser(description="Hybrid discovery + safety-gated pfSense training VM NAT sync")
    parser.add_argument("--config", default="config.json", help="Path to config JSON")
    parser.add_argument("--dry-run", action="store_true", help="Print API calls only")
    parser.add_argument("--generate-only", action="store_true", help="Only generate mapping files")
    parser.add_argument("--validate-config", action="store_true", help="Validate configuration and exit")
    args = parser.parse_args()

    config_path = Path(args.config).resolve()
    if not config_path.exists():
        print(f"Config not found: {config_path}", file=sys.stderr)
        return 1

    config = load_json_file(config_path)
    output_dir = resolve_path(config_path, config.get("outputDir", "./generated"))
    state_path = resolve_path(config_path, config.get("runtime", {}).get("stateFile", "./generated/runtime-state.json"))

    required_top = ["api", "discovery", "mapping", "nat"]
    for key in required_top:
        if key not in config:
            print(f"Missing config key: {key}", file=sys.stderr)
            return 1

    if args.validate_config:
        print("Configuration is valid.")
        print(f"Config: {config_path}")
        print(f"OutputDir: {output_dir}")
        print(f"StateFile: {state_path}")
        return 0

    base_url = str(config["api"]["baseUrl"]).rstrip("/")
    try:
        headers = resolve_api_headers(config["api"])
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    timeout = int(config["api"].get("timeoutSeconds", 20))
    verify_tls = not bool(config["api"].get("skipCertificateCheck", True))

    session = requests.Session()

    try:
        discovered = discover_clients(
            session=session,
            base_url=base_url,
            headers=headers,
            config=config,
            dry_run=args.dry_run,
        )

        if args.dry_run:
            print("Dry-run mode: discovery calls emitted. Skipping reconciliation.")
            return 0

        eligible_clients, gate_stats = apply_safety_gates(discovered, config)
        print(
            "Safety gates result: discovered={discovered}, eligible={eligible}, rejected_unknown_age={unknown}, rejected_stale={stale}".format(
                discovered=gate_stats["discovered"],
                eligible=gate_stats["eligible"],
                unknown=gate_stats["rejectedUnknownAge"],
                stale=gate_stats["rejectedStale"],
            )
        )

        desired = build_desired_mappings(config, eligible_clients)
        csv_path, md_path = export_mapping_table(output_dir, desired)
        print(f"Generated mapping tables: {csv_path} and {md_path}")

        if args.generate_only:
            print("Generate-only mode complete.")
            return 0

        nat = config["nat"]
        list_response = request_json(
            session=session,
            method=nat.get("listMethod", "GET"),
            url=build_url(base_url, nat["listEndpoint"]),
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

        safety = config.get("safety", {})
        check_port_open = bool(safety.get("checkTargetPortOpen", False))
        check_timeout_ms = int(safety.get("targetPortCheckTimeoutMs", 800))
        stale_mode = str(safety.get("staleRuleMode", "disabled")).strip().lower()
        stale_grace_minutes = int(safety.get("staleGraceMinutes", 180))

        desired_desc = {row["description"] for row in desired}
        created = 0
        skipped_existing = 0
        skipped_port_closed = 0

        for row in desired:
            if row["description"] in existing:
                skipped_existing += 1
                continue

            if check_port_open and not can_connect(row["ip"], int(row["targetPort"]), check_timeout_ms):
                skipped_port_closed += 1
                print(f"Skipping create (target port closed): {row['description']} ({row['ip']}:{row['targetPort']})")
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

            request_json(
                session=session,
                method=nat.get("createMethod", "POST"),
                url=build_url(base_url, nat["createEndpoint"]),
                headers=headers,
                verify_tls=verify_tls,
                timeout=timeout,
                body=payload,
                dry_run=False,
            )
            created += 1

        runtime_state = load_runtime_state(state_path)
        stale_first_seen: Dict[str, str] = runtime_state.get("staleFirstSeen", {})
        now_ts = time.time()

        removed = 0
        stale_candidates = 0
        prefix = str(config["mapping"]["descriptionPrefix"])
        next_stale_map: Dict[str, str] = {}

        for desc, item in existing.items():
            if not desc.startswith(prefix):
                continue
            if desc in desired_desc:
                continue

            stale_candidates += 1
            first_seen_iso = stale_first_seen.get(desc)
            if not first_seen_iso:
                first_seen_iso = datetime.now(timezone.utc).isoformat()

            next_stale_map[desc] = first_seen_iso

            if stale_mode == "disabled" or stale_mode == "mark":
                continue

            if stale_mode != "delete_after_grace":
                raise ValueError("safety.staleRuleMode must be one of: disabled, mark, delete_after_grace")

            try:
                first_seen_ts = datetime.fromisoformat(first_seen_iso.replace("Z", "+00:00")).timestamp()
            except ValueError:
                first_seen_ts = now_ts

            age_seconds = max(0.0, now_ts - first_seen_ts)
            if age_seconds < (stale_grace_minutes * 60):
                continue

            rule_id = item.get("id")
            if not rule_id:
                print(f"Skipping stale delete without id: {desc}")
                continue

            endpoint_template = nat.get("deleteEndpointTemplate")
            if not endpoint_template:
                raise ValueError("nat.deleteEndpointTemplate is required for stale rule deletion")

            request_json(
                session=session,
                method=nat.get("deleteMethod", "DELETE"),
                url=build_url(base_url, endpoint_template.replace("{id}", str(rule_id))),
                headers=headers,
                verify_tls=verify_tls,
                timeout=timeout,
                body=None,
                dry_run=False,
            )
            removed += 1
            next_stale_map.pop(desc, None)

        runtime_state["staleFirstSeen"] = next_stale_map
        write_json_file(state_path, runtime_state)

        changed = created + removed
        apply_endpoint = nat.get("applyEndpoint")
        if changed > 0 and apply_endpoint:
            request_json(
                session=session,
                method=nat.get("applyMethod", "POST"),
                url=build_url(base_url, apply_endpoint),
                headers=headers,
                verify_tls=verify_tls,
                timeout=timeout,
                body=nat.get("applyBody"),
                dry_run=False,
            )

        summary = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "discovered": gate_stats["discovered"],
            "eligible": gate_stats["eligible"],
            "rejectedUnknownAge": gate_stats["rejectedUnknownAge"],
            "rejectedStale": gate_stats["rejectedStale"],
            "desired": len(desired),
            "created": created,
            "skippedExisting": skipped_existing,
            "skippedTargetPortClosed": skipped_port_closed,
            "staleCandidates": stale_candidates,
            "removed": removed,
            "staleRuleMode": stale_mode,
            "staleGraceMinutes": stale_grace_minutes,
            "applied": changed > 0 and bool(apply_endpoint),
        }

        summary_path = output_dir / "sync-summary.json"
        write_json_file(summary_path, summary)

        print(
            "Sync complete. desired={desired}, created={created}, skipped_existing={skipped_existing}, skipped_port_closed={skipped_port_closed}, stale_candidates={stale_candidates}, removed={removed}, summary={summary_path}".format(
                desired=len(desired),
                created=created,
                skipped_existing=skipped_existing,
                skipped_port_closed=skipped_port_closed,
                stale_candidates=stale_candidates,
                removed=removed,
                summary_path=summary_path,
            )
        )
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
