resource "aws_cloudwatch_dashboard" "ec2_dashboard" {
  dashboard_name = "EC2-GoldenAMI-Dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        x    = 0
        y    = 0
        width  = 12
        height = 6

        properties = {
          region = "eu-central-1"
          view   = "timeSeries"
          title  = "EC2 CPU Utilization"
          stat   = "Average"
          period = 300

          metrics = [
            [ "AWS/EC2", "CPUUtilization", "InstanceId", "*" ]
          ]

          annotations = {}
        }
      },
      {
        type = "metric"
        x    = 12
        y    = 0
        width  = 12
        height = 6

        properties = {
          region = "eu-central-1"
          view   = "timeSeries"
          title  = "EC2 Network In"
          stat   = "Sum"
          period = 300

          metrics = [
            [ "AWS/EC2", "NetworkIn", "InstanceId", "*" ]
          ]

          annotations = {}
        }
      }
    ]
  })
}

