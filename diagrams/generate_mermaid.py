import json
import argparse
from datetime import datetime, UTC

parser = argparse.ArgumentParser()
parser.add_argument("--payload", required=True)
parser.add_argument("--out", required=True)
args = parser.parse_args()

with open(args.payload) as f:
    payload = json.load(f)

lines = []
lines.append("flowchart TB\n")

# Common pipeline
lines += [
    "API[API Gateway]",
    "S3[S3 Payload Bucket]",
    "J[Jenkins]",
    "TF[Terraform]",
    "ANS[Ansible]",
    "API --> S3",
    "S3 --> J",
    "J --> TF",
]

service = payload["service_type"]

# =====================
# EC2 DIAGRAM
# =====================
if service == "ec2":
    lines.append("TF --> ANS")
    lines.append("subgraph AWS_EC2 [EC2 Lab]")
    lines.append(
        f'EC2_VM["EC2: {payload.get("name","VM")}<br/>'
        f'{payload.get("instance_type","t3.medium")}"]'
    )
    lines.append("ANS --> EC2_VM")
    lines.append("end")

# =====================
# EKS DIAGRAM
# =====================
elif service == "eks":
    lines.append("subgraph AWS_EKS [EKS Lab]")
    lines.append(
        f'EKS["EKS Cluster<br/>{payload.get("cluster_name","eks")}"]'
    )
    lines.append(
        f'NODE["Worker Nodes<br/>{payload.get("node_type","t3.large")}"]'
    )
    lines.append("TF --> EKS")
    lines.append("EKS --> NODE")
    lines.append("end")

# Footer
lines.append(
    f'NOTE["Generated {datetime.now(UTC).isoformat()}"]'
)

with open(args.out, "w") as f:
    f.write("\n".join(lines))

print("[OK] Mermaid file generated")

