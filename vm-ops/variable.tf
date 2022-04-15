variable "vm_admin_username" {
  type = string
  sensitive = true
}

variable "vm_admin_password" {
  type = string
  sensitive = true
}

variable "default_resource_tags" {
  type = map(string)
}