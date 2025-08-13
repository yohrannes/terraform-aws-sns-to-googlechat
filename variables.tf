variable "gchat_webhook" {
    description = "Google Chat webhook URL for sending alerts"
    type        = string
}

variable "alert_name" {
    description = "Name of the alert"
    type        = string
    default     = "purpose-X-alert"
}