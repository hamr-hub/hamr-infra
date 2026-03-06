#!/usr/bin/env python3
import os
import sys
from pathlib import Path

from alibabacloud_alidns20150109.client import Client
from alibabacloud_alidns20150109 import models as dns_models
from alibabacloud_tea_openapi import models as open_api_models

ACCESS_KEY_ID = os.environ.get("ALIBABA_CLOUD_ACCESS_KEY_ID")
ACCESS_KEY_SECRET = os.environ.get("ALIBABA_CLOUD_ACCESS_KEY_SECRET")
CONF_FILE = Path(__file__).parent / "dns-records.conf"


def create_client() -> Client:
    config = open_api_models.Config(
        access_key_id=ACCESS_KEY_ID,
        access_key_secret=ACCESS_KEY_SECRET,
        endpoint="alidns.aliyuncs.com",
    )
    return Client(config)


def parse_conf(path: Path) -> list[dict]:
    records = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        if len(parts) != 4:
            continue
        fqdn, rtype, value, ttl = parts
        fqdn = fqdn.strip()
        rtype = rtype.strip()
        value = value.strip()
        ttl = int(ttl.strip())

        parts2 = fqdn.split(".", 1)
        if len(parts2) == 2 and "." in parts2[1]:
            rr = parts2[0]
            domain = parts2[1]
        else:
            rr = "@"
            domain = fqdn

        records.append({"rr": rr, "domain": domain, "type": rtype, "value": value, "ttl": ttl})
    return records


def list_records(client: Client, domain: str) -> list[dict]:
    result = []
    page = 1
    page_size = 500
    while True:
        req = dns_models.DescribeDomainRecordsRequest(
            domain_name=domain,
            page_number=page,
            page_size=page_size,
        )
        resp = client.describe_domain_records(req)
        records = resp.body.domain_records.record or []
        result.extend(records)
        if len(records) < page_size:
            break
        page += 1
    return result


def sync_record(client: Client, record: dict, existing: list[dict]):
    rr = record["rr"]
    domain = record["domain"]
    rtype = record["type"]
    value = record["value"]
    ttl = record["ttl"]

    match = next(
        (r for r in existing if r.rr == rr and r.type == rtype),
        None,
    )

    if match is None:
        req = dns_models.AddDomainRecordRequest(
            domain_name=domain,
            rr=rr,
            type=rtype,
            value=value,
            ttl=ttl,
        )
        client.add_domain_record(req)
        print(f"  [ADD]    {rr}.{domain} {rtype} {value}")
    elif match.value != value or match.ttl != ttl:
        req = dns_models.UpdateDomainRecordRequest(
            record_id=match.record_id,
            rr=rr,
            type=rtype,
            value=value,
            ttl=ttl,
        )
        client.update_domain_record(req)
        print(f"  [UPDATE] {rr}.{domain} {rtype} {match.value} -> {value}")
    else:
        print(f"  [OK]     {rr}.{domain} {rtype} {value}")


def main():
    if not ACCESS_KEY_ID or not ACCESS_KEY_SECRET:
        print("错误：请设置环境变量 ALIBABA_CLOUD_ACCESS_KEY_ID 和 ALIBABA_CLOUD_ACCESS_KEY_SECRET")
        sys.exit(1)

    client = create_client()
    records = parse_conf(CONF_FILE)

    domains: dict[str, list[dict]] = {}
    for r in records:
        domains.setdefault(r["domain"], []).append(r)

    for domain, domain_records in domains.items():
        print(f"\n域名: {domain}")
        existing = list_records(client, domain)
        for record in domain_records:
            sync_record(client, record, existing)

    print("\n完成！")


if __name__ == "__main__":
    main()
