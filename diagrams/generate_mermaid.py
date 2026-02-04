import json
import argparse
from datetime import datetime, UTC

def header(lines):
    lines.extend([
        "flowchart TB",
        "",
        "Client[Client / API Request]",
        "S3[S3 Payload Bucket]",
        "J[Jenkins Pipeline]",
        "TF[Terraform Apply]",
        "ANS[Ansible Configuration]",
        "",
        "Client --> S3",
        "S3 --> J",
        "J --> TF",
        "TF --> ANS",
        ""
    ])

def ec2_diagram(lines, payload):
    lines.append("subgraph AWS_EC2 [AWS EC2 Lab]")

    for key, inst in payload["instances"].items():
        node_id = f"EC2_{key.replace('-', '_')}"
        label = (
            f"EC2 Instance<br/>"
            f"<b>{inst.get('name')}</b><br/>"
            f"Type: {inst.get('instance_type')}<br/>"
            f"Subnet: {inst.get('subnet_id')}<br/>"
            f"SGs: {', '.join(inst.get('security_groups', []))}"
        )

        lines.append(f'{node_id}["{label}"]')
        lines.append(f"ANS --> {node_id}")

        # Tools
        tools = inst.get("tools_to_install", [])
        if tools:
            tool_node = f"{node_id}_TOOLS"
            lines.append(f'{tool_node}["Installed Tools<br/>{", ".join(tools)}"]')
            lines.append(f"{node_id} --> {tool_node}")

    lines.append("end")
    lines.append("")

def eks_diagram(lines, payload):
    lines.append("subgraph AWS_EKS [AWS EKS Lab]")
    lines.append('EKS["EKS Cluster"]')
    lines.append("ANS --> EKS")
    lines.append("end")
    lines.append("")

def footer(lines):
    ts = datetime.now(UTC).isoformat()
    lines.append(f'NOTE["Generated automatically<br/>{ts}"]')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--payload", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    with open(args.payload) as f:
        payload = json.load(f)

    lines = []
    header(lines)

    if payload["service_type"] == "ec2":
        ec2_diagram(lines, payload)
    elif payload["service_type"] == "eks":
        eks_diagram(lines, payload)

    footer(lines)

    with open(args.out, "w") as f:
        f.write("\n".join(lines))

    print("[OK] Mermaid diagram generated")

if __name__ == "__main__":
    main()
