import argparse
import json
import os
import re
import sys
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, Optional

import requests


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def get_nested(data: Any, path: str) -> Any:
    if not path:
        return data

    current = data
    for token in path.split("."):
        if isinstance(current, list):
            if not token.isdigit():
                return None
            idx = int(token)
            if idx < 0 or idx >= len(current):
                return None
            current = current[idx]
        elif isinstance(current, dict):
            current = current.get(token)
        else:
            return None

        if current is None:
            return None

    return current


def normalize_url(base_url: str, endpoint: str) -> str:
    return f"{base_url.rstrip('/')}/{endpoint.lstrip('/')}"


def replace_placeholders(value: Any, context: Dict[str, Any]) -> Any:
    if isinstance(value, dict):
        return {k: replace_placeholders(v, context) for k, v in value.items()}
    if isinstance(value, list):
        return [replace_placeholders(v, context) for v in value]
    if isinstance(value, str):
        out = value
        for key, replacement in context.items():
            out = out.replace("{" + key + "}", str(replacement))

        if re.fullmatch(r"\d+", out):
            return int(out)
        if out.lower() in {"true", "false"}:
            return out.lower() == "true"
        return out

    return value


def api_call(
    session: requests.Session,
    base_url: str,
    endpoint: str,
    method: str,
    headers: Dict[str, str],
    verify_tls: bool,
    timeout_sec: int,
    body: Optional[Dict[str, Any]],
    dry_run: bool,
) -> Any:
    url = normalize_url(base_url, endpoint)
    method = method.upper()

    if dry_run:
        print(f"DRY-RUN {method} {url}")
        if body is not None:
            print(json.dumps(body, indent=2))
        return None

    response = session.request(
        method=method,
        url=url,
        headers=headers,
        json=body,
        timeout=timeout_sec,
        verify=verify_tls,
    )
    response.raise_for_status()

    if not response.text.strip():
        return None

    try:
        return response.json()
    except ValueError:
        return {"raw": response.text}


def find_interface_id(interfaces_payload: Any, cfg: Dict[str, Any]) -> str:
    interfaces_path = cfg["interface"]["discover"].get("listResponsePath", "")
    interfaces = get_nested(interfaces_payload, interfaces_path) if interfaces_path else interfaces_payload

    if not isinstance(interfaces, list):
        raise ValueError("Interface discovery response did not resolve to a list. Update listResponsePath.")

    match_field = cfg["interface"]["discover"].get("matchField", "descr")
    match_value = cfg["interface"]["discover"]["matchValue"]
    id_fields = cfg["interface"]["discover"].get("idFields", ["id", "if", "interface"])

    for item in interfaces:
        if not isinstance(item, dict):
            continue
        if str(item.get(match_field, "")) != str(match_value):
            continue

        for id_field in id_fields:
            if item.get(id_field) is not None:
                return str(item[id_field])

    raise ValueError(
        f"Unable to find interface where {match_field}={match_value}. "
        "Update interface.discover match config."
    )


def find_matching_rule_id(rules_payload: Any, cfg: Dict[str, Any], interface_id: str) -> Optional[int]:
    rules_path = cfg["firewall"]["ensureRule"].get("listResponsePath", "")
    rules = get_nested(rules_payload, rules_path) if rules_path else rules_payload

    if not isinstance(rules, list):
        return None

    expected_source = str(cfg["firewall"]["ensureRule"].get("matchSource", "any"))
    expected_destination = str(cfg["firewall"]["ensureRule"].get("matchDestination", "any"))
    match_descr = cfg["firewall"]["ensureRule"].get("matchDescription")
    for item in rules:
        if not isinstance(item, dict):
            continue

        interfaces = item.get("interface")
        has_interface = (
            isinstance(interfaces, list) and interface_id in interfaces
        ) or str(item.get("interface", "")) == interface_id

        if not has_interface:
            continue
        if item.get("type") != "pass":
            continue
        if str(item.get("source", "")) != expected_source:
            continue
        if str(item.get("destination", "")) != expected_destination:
            continue
        if match_descr and str(item.get("descr", "")) != str(match_descr):
            continue

        try:
            return int(item.get("id"))
        except (TypeError, ValueError):
            return None

    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Configure pfSense training interface and DHCP via API")
    parser.add_argument("--config", default="api-config.json", help="Path to API config file")
    parser.add_argument("--dry-run", action="store_true", help="Show API calls without applying changes")
    args = parser.parse_args()

    config_path = Path(args.config).resolve()
    if not config_path.exists():
        print(f"Config file not found: {config_path}", file=sys.stderr)
        return 1

    cfg = load_json(config_path)

    base_url = cfg["api"]["baseUrl"]
    auth_type = cfg["api"].get("authType", "bearer")
    timeout_sec = int(cfg["api"].get("timeoutSeconds", 20))
    verify_tls = not bool(cfg["api"].get("skipCertificateCheck", True))

    if auth_type == "basic":
        import base64
        username = cfg["api"]["username"]
        password = os.getenv(cfg["api"]["passwordEnvVar"])
        if not password:
            print(f"Environment variable not set: {cfg['api']['passwordEnvVar']}", file=sys.stderr)
            return 1
        b64 = base64.b64encode(f"{username}:{password}".encode()).decode()
        auth_header = f"Basic {b64}"
    else:
        token = os.getenv(cfg["api"].get("tokenEnvVar", ""))
        if not token:
            print(f"Environment variable not set: {cfg['api'].get('tokenEnvVar','')}", file=sys.stderr)
            return 1
        auth_header = f"Bearer {token}"

    headers = {
        "Authorization": auth_header,
        "Accept": "application/json",
        "Content-Type": "application/json",
    }

    session = requests.Session()

    try:
        # 1) Discover interface id for training-vm-lan mapping.
        discover = cfg["interface"]["discover"]
        discover_resp = api_call(
            session=session,
            base_url=base_url,
            endpoint=discover["listEndpoint"],
            method=discover.get("listMethod", "GET"),
            headers=headers,
            verify_tls=verify_tls,
            timeout_sec=timeout_sec,
            body=discover.get("listBody"),
            dry_run=args.dry_run,
        )

        if args.dry_run:
            interface_id = cfg["interface"]["discover"].get("dryRunInterfaceId", "opt2")
            print(f"DRY-RUN using interface id placeholder: {interface_id}")
        else:
            interface_id = find_interface_id(discover_resp, cfg)
            print(f"Resolved training interface id: {interface_id}")

        # 2) Apply interface static IPv4 config.
        iface_cfg = cfg["interface"]["configure"]
        iface_endpoint = iface_cfg["endpointTemplate"].replace("{interface_id}", interface_id)
        iface_payload = replace_placeholders(
            deepcopy(iface_cfg["payloadTemplate"]),
            {
                "interface_id": interface_id,
                "interface_description": cfg["desired"].get("interfaceDescription", "TRAINING-LAN"),
                "ip_address": cfg["desired"]["interfaceIp"],
                "subnet_bits": cfg["desired"]["subnetBits"],
            },
        )

        api_call(
            session=session,
            base_url=base_url,
            endpoint=iface_endpoint,
            method=iface_cfg.get("method", "POST"),
            headers=headers,
            verify_tls=verify_tls,
            timeout_sec=timeout_sec,
            body=iface_payload,
            dry_run=args.dry_run,
        )

        # 3) Apply DHCP config for the same interface.
        dhcp_cfg = cfg["dhcp"]["configure"]
        dhcp_endpoint = dhcp_cfg["endpointTemplate"].replace("{interface_id}", interface_id)
        dhcp_payload = replace_placeholders(
            deepcopy(dhcp_cfg["payloadTemplate"]),
            {
                "interface_id": interface_id,
                "dhcp_enabled": cfg["desired"].get("dhcpEnabled", True),
                "dhcp_range_start": cfg["desired"]["dhcpRangeStart"],
                "dhcp_range_end": cfg["desired"]["dhcpRangeEnd"],
                "subnet": cfg["desired"]["subnetCidr"],
                "gateway": cfg["desired"]["interfaceIp"],
            },
        )

        api_call(
            session=session,
            base_url=base_url,
            endpoint=dhcp_endpoint,
            method=dhcp_cfg.get("method", "POST"),
            headers=headers,
            verify_tls=verify_tls,
            timeout_sec=timeout_sec,
            body=dhcp_payload,
            dry_run=args.dry_run,
        )

        # 4) Ensure interface firewall pass rule for internet egress.
        fw_cfg = cfg.get("firewall", {}).get("ensureRule")
        if fw_cfg:
            fw_list_resp = api_call(
                session=session,
                base_url=base_url,
                endpoint=fw_cfg["listEndpoint"],
                method=fw_cfg.get("listMethod", "GET"),
                headers=headers,
                verify_tls=verify_tls,
                timeout_sec=timeout_sec,
                body=fw_cfg.get("listBody"),
                dry_run=args.dry_run,
            )

            existing_rule_id = None if args.dry_run else find_matching_rule_id(fw_list_resp, cfg, interface_id)
            if args.dry_run:
                print("DRY-RUN firewall rule existence check skipped; showing create call.")

            if existing_rule_id is None:
                fw_create_endpoint = fw_cfg["createEndpoint"]
                fw_create_payload = replace_placeholders(
                    deepcopy(fw_cfg["createPayloadTemplate"]),
                    {"interface_id": interface_id},
                )
                api_call(
                    session=session,
                    base_url=base_url,
                    endpoint=fw_create_endpoint,
                    method=fw_cfg.get("createMethod", "POST"),
                    headers=headers,
                    verify_tls=verify_tls,
                    timeout_sec=timeout_sec,
                    body=fw_create_payload,
                    dry_run=args.dry_run,
                )
                if not args.dry_run:
                    print("Created training LAN firewall pass rule.")
            else:
                print(f"Firewall pass rule already exists (id={existing_rule_id}); skipping create.")

        # 5) Apply changes.
        apply_cfg = cfg.get("apply", {})
        apply_endpoint = apply_cfg.get("endpoint")
        if apply_endpoint:
            api_call(
                session=session,
                base_url=base_url,
                endpoint=apply_endpoint,
                method=apply_cfg.get("method", "POST"),
                headers=headers,
                verify_tls=verify_tls,
                timeout_sec=timeout_sec,
                body=apply_cfg.get("body"),
                dry_run=args.dry_run,
            )

        print("Done: interface and DHCP API workflow completed.")
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
