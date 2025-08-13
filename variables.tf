variable "gchat_webhook" {
    description = "Google Chat webhook URL for sending alerts"
    type        = string
    default     = null
}

variable "alert_name" {
    description = "Name of the SNS alert"
    type        = string
    default     = "sns-alert"
}