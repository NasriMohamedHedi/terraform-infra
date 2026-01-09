resource "aws_cloudwatch_dashboard" "ec2_dashboard" {
  dashboard_name = "EC2-GoldenAMI-Dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric",
        width = 12,
        height = 6,
        properties = {
          metrics = [
            [ "EC2/GoldenAMI", "cpu_usage_idle", "InstanceId", "*" ]
          ],
          period = 300,
          stat = "Average",
          title = "CPU Idle (%)"
        }
      },
      {
        type = "metric",
        width = 12,
        height = 6,
        properties = {
          metrics = [
            [ "EC2/GoldenAMI", "mem_used_percent", "InstanceId", "*" ]
          ],
          period = 300,
          stat = "Average",
          title = "Memory Used (%)"
        }
      }
    ]
  })
}

