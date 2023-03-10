resource "null_resource" "user_data" {
  triggers = {
    user_data = var.user_data
  }
}

resource "azurerm_linux_virtual_machine_scale_set" "vault_cluster" {
  admin_username      = var.ssh_username
  instances           = var.instance_count
  location            = var.resource_group.location
  name                = var.scale_set_name
  overprovision       = false
  resource_group_name = var.resource_group.name
  sku                 = var.instance_type
  user_data           = var.user_data
  zone_balance        = var.zones == null ? false : true
  zones               = var.zones

  additional_capabilities {
    ultra_ssd_enabled = var.ultra_ssd_enabled
  }

  dynamic "admin_ssh_key" {
    for_each = var.ssh_public_key == "" ? [] : [1]
    content {
      username   = var.ssh_username
      public_key = var.ssh_public_key
    }
  }

  network_interface {
    name    = "${var.resource_name_prefix}-vault"
    primary = true

    ip_configuration {
      application_gateway_backend_address_pool_ids = var.backend_address_pool_ids
      application_security_group_ids               = var.application_security_group_ids
      name                                         = "${var.resource_name_prefix}-vault"
      primary                                      = true
      subnet_id                                    = var.subnet_id
    }
  }

  identity {
    identity_ids = var.identity_ids
    type         = "UserAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    disk_size_gb         = 1024
    storage_account_type = var.os_disk_type
  }

  source_image_reference {
    offer     = "0001-com-ubuntu-server-focal"
    publisher = "Canonical"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  tags = merge(
    {
      "${var.resource_name_prefix}-vault" = "server"
    },
    var.common_tags
  )

  lifecycle {
    replace_triggered_by = [
      null_resource.user_data
    ]
  }
}

resource "azurerm_virtual_machine_scale_set_extension" "vault_health" {
  auto_upgrade_minor_version   = true
  name                         = "${var.resource_name_prefix}-vault-health"
  publisher                    = "Microsoft.ManagedServices"
  type                         = "ApplicationHealthLinux"
  type_handler_version         = "1.0"
  virtual_machine_scale_set_id = azurerm_linux_virtual_machine_scale_set.vault_cluster.id

  settings = jsonencode({
    "protocol" : "https",
    "port" : 8200,
    "requestPath" : var.health_check_path
  })
}
