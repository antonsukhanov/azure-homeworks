terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.2.0"
    }
  }

  required_version = ">= 1.1.8"
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

data "azurerm_client_config" "cli" {}

# Creating project resource group.

resource "azurerm_resource_group" "rg-as2-vm-ops" {
  name     = "rg-as2-vm-ops"
  location = "westeurope"

  tags = var.default_resource_tags
}

# Creating key vault and storing VM's admin password.

resource "azurerm_key_vault" "kv-as2-vm-ops" {
  name                        = "kv-as2-vm-ops"
  location                    = azurerm_resource_group.rg-as2-vm-ops.location
  resource_group_name         = azurerm_resource_group.rg-as2-vm-ops.name
  tenant_id                   = data.azurerm_client_config.cli.tenant_id

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.cli.tenant_id
    object_id = data.azurerm_client_config.cli.object_id

    secret_permissions = [
      "Backup",
      "Delete",
      "Get",
      "List",
      "Purge",
      "Recover",
      "Restore",
      "Set"
    ]
  }

  tags = var.default_resource_tags
}

resource "azurerm_key_vault_secret" "kvs-pwd-vm-as2-vm-ops" {
  name         = "kvs-pwd-vm-as2-vm-ops"
  value        = var.vm_admin_password
  key_vault_id = azurerm_key_vault.kv-as2-vm-ops.id

  tags = var.default_resource_tags
}

data "azurerm_key_vault_secret" "kvs-pwd-vm-as2-vm-ops" {
  name         = "kvs-pwd-vm-as2-vm-ops"
  key_vault_id = azurerm_key_vault.kv-as2-vm-ops.id

  depends_on = [
    azurerm_key_vault_secret.kvs-pwd-vm-as2-vm-ops,
  ]
}

# Creating VM.

resource "azurerm_public_ip" "pip-vm-as2-vm-ops" {
  name                = "pip-vm-as2-vm-ops"
  resource_group_name = azurerm_resource_group.rg-as2-vm-ops.name
  location            = azurerm_resource_group.rg-as2-vm-ops.location
  allocation_method   = "Dynamic"

  tags = var.default_resource_tags
}

resource "azurerm_virtual_network" "vnet-as2-vm-ops" {
  name                = "vnet-as2-vm-ops"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg-as2-vm-ops.location
  resource_group_name = azurerm_resource_group.rg-as2-vm-ops.name

  tags = var.default_resource_tags
}

resource "azurerm_subnet" "snet-vnet-as2-vm-ops" {
  name                 = "snet-vnet-as2-vm-ops"
  resource_group_name  = azurerm_resource_group.rg-as2-vm-ops.name
  virtual_network_name = azurerm_virtual_network.vnet-as2-vm-ops.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_network_interface" "nic-vm-as2-vm-ops" {
  name                = "nic-vm-as2-vm-ops"
  location            = azurerm_resource_group.rg-as2-vm-ops.location
  resource_group_name = azurerm_resource_group.rg-as2-vm-ops.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.snet-vnet-as2-vm-ops.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.pip-vm-as2-vm-ops.id
  }

  tags = var.default_resource_tags
}

resource "azurerm_windows_virtual_machine" "vm-as2-vm-ops" {
  name                = "vm-as2-vm-ops"
  resource_group_name = azurerm_resource_group.rg-as2-vm-ops.name
  location            = azurerm_resource_group.rg-as2-vm-ops.location
  size                = "Standard_B2s"
  admin_username      = var.vm_admin_username
  admin_password      = data.azurerm_key_vault_secret.kvs-pwd-vm-as2-vm-ops.value
  network_interface_ids = [
    azurerm_network_interface.nic-vm-as2-vm-ops.id,
  ]

  os_disk {
    name = "osdisk-vm-as2-vm-ops"
    caching = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }

  tags = var.default_resource_tags
}

# Installing web server role on VM.

resource "azurerm_virtual_machine_extension" "ext-iis-vm-as2-vm-ops" {
  name                 = "ext-iis-vm-as2-vm-ops"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm-as2-vm-ops.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  auto_upgrade_minor_version = true

  protected_settings = <<SETTINGS
    {
        "commandToExecute": "powershell.exe Install-WindowsFeature -name Web-Server -IncludeManagementTools"
    }
SETTINGS

  tags = var.default_resource_tags
}

# Creating recovery services vault and scheduling VM backups.

resource "azurerm_recovery_services_vault" "rsv-as2-vm-ops" {
  name                = "rsv-as2-vm-ops"
  location            = azurerm_resource_group.rg-as2-vm-ops.location
  resource_group_name = azurerm_resource_group.rg-as2-vm-ops.name
  sku                 = "Standard"

  tags = var.default_resource_tags
}

resource "azurerm_backup_policy_vm" "WeeklyPolicy" {
  name                = "WeeklyPolicy"
  resource_group_name = azurerm_resource_group.rg-as2-vm-ops.name
  recovery_vault_name = azurerm_recovery_services_vault.rsv-as2-vm-ops.name

  timezone = "UTC"

  backup {
    frequency = "Weekly"
    weekdays  = ["Saturday"]
    time      = "00:00"
  }

  retention_weekly {
    count = 1
    weekdays = [ "Saturday" ]
  }
}

resource "azurerm_backup_protected_vm" "vm-as2-vm-ops" {
  resource_group_name = azurerm_resource_group.rg-as2-vm-ops.name
  recovery_vault_name = azurerm_recovery_services_vault.rsv-as2-vm-ops.name
  source_vm_id        = azurerm_windows_virtual_machine.vm-as2-vm-ops.id
  backup_policy_id    = azurerm_backup_policy_vm.WeeklyPolicy.id
}

# Creating the file share.

resource "azurerm_storage_account" "stas2vmops" {
  name                     = "stas2vmops"
  resource_group_name      = azurerm_resource_group.rg-as2-vm-ops.name
  location                 = azurerm_resource_group.rg-as2-vm-ops.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  access_tier = "Cool"

  enable_https_traffic_only = true
  shared_access_key_enabled = true

  tags = var.default_resource_tags
}

resource "azurerm_storage_share" "attached" {
  name                 = "attached"
  storage_account_name = azurerm_storage_account.stas2vmops.name
  quota                = 1
}

resource "azurerm_storage_container" "vm-custom-scripts" {
  name                  = "vm-custom-scripts"
  storage_account_name  = azurerm_storage_account.stas2vmops.name
  container_access_type = "private"
}
