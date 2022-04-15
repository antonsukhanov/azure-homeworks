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

resource "azurerm_resource_group" "rg-as2-labs-hw1" {
  name     = "rg-as2-labs-hw1"
  location = "westeurope"

  tags = var.default_resource_tags
}

resource "azurerm_key_vault" "kv-as2-labs-hw1" {
  name                        = "kv-as2-labs-hw1"
  location                    = azurerm_resource_group.rg-as2-labs-hw1.location
  resource_group_name         = azurerm_resource_group.rg-as2-labs-hw1.name
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

resource "azurerm_key_vault_secret" "kvs-pwd-vm-as2-labs-hw1" {
  name         = "kvs-pwd-vm-as2-labs-hw1"
  value        = var.vm_admin_password
  key_vault_id = azurerm_key_vault.kv-as2-labs-hw1.id

  tags = var.default_resource_tags
}

data "azurerm_key_vault_secret" "kvs-pwd-vm-as2-labs-hw1" {
  name         = "kvs-pwd-vm-as2-labs-hw1"
  key_vault_id = azurerm_key_vault.kv-as2-labs-hw1.id

  depends_on = [
    azurerm_key_vault_secret.kvs-pwd-vm-as2-labs-hw1,
  ]
}

resource "azurerm_public_ip" "pip-vm-as2-labs-hw1" {
  name                = "pip-vm-as2-labs-hw1"
  resource_group_name = azurerm_resource_group.rg-as2-labs-hw1.name
  location            = azurerm_resource_group.rg-as2-labs-hw1.location
  allocation_method   = "Dynamic"

  tags = var.default_resource_tags
}

resource "azurerm_virtual_network" "vnet-as2-labs-hw1" {
  name                = "vnet-as2-labs-hw1"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg-as2-labs-hw1.location
  resource_group_name = azurerm_resource_group.rg-as2-labs-hw1.name

  tags = var.default_resource_tags
}

resource "azurerm_subnet" "snet-vnet-as2-labs-hw1" {
  name                 = "snet-vnet-as2-labs-hw1"
  resource_group_name  = azurerm_resource_group.rg-as2-labs-hw1.name
  virtual_network_name = azurerm_virtual_network.vnet-as2-labs-hw1.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_network_interface" "nic-vm-as2-labs-hw1" {
  name                = "nic-vm-as2-labs-hw1"
  location            = azurerm_resource_group.rg-as2-labs-hw1.location
  resource_group_name = azurerm_resource_group.rg-as2-labs-hw1.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.snet-vnet-as2-labs-hw1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.pip-vm-as2-labs-hw1.id
  }

  tags = var.default_resource_tags
}

resource "azurerm_windows_virtual_machine" "vm-as2-labs-hw1" {
  name                = "vm-as2-labs-hw1"
  resource_group_name = azurerm_resource_group.rg-as2-labs-hw1.name
  location            = azurerm_resource_group.rg-as2-labs-hw1.location
  size                = "Standard_B2s"
  admin_username      = var.vm_admin_username
  admin_password      = data.azurerm_key_vault_secret.kvs-pwd-vm-as2-labs-hw1.value
  network_interface_ids = [
    azurerm_network_interface.nic-vm-as2-labs-hw1.id,
  ]

  os_disk {
    name = "osdisk-vm-as2-labs-hw1"
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

resource "azurerm_virtual_machine_extension" "ext-iis-vm-as2-labs-hw1" {
  name                 = "ext-iis-vm-as2-labs-hw1"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm-as2-labs-hw1.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  protected_settings = <<SETTINGS
    {
        "commandToExecute": "powershell.exe Install-WindowsFeature -name Web-Server -IncludeManagementTools"
    }
SETTINGS

  tags = var.default_resource_tags
}
