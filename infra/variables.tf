variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for all resource names; change to stand up a second stack."
  type        = string
  default     = "guitar-tabs"
}

variable "alert_email" {
  description = "Email for the monthly billing alert."
  type        = string
}
