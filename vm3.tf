variable "resourcename" {
  default = "DL2ResourceGroup"
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
}

# Create a resource group if it doesn’t exist
resource "azurerm_resource_group" "DL2terraformgroup" {
    name     = "DL2ResourceGroup"
    location = "eastus"

    tags {
        environment = "Terraform Demo"
    }
}

# Create virtual network
resource "azurerm_virtual_network" "DL2terraformnetwork" {
    name                = "DL2Vnet"
    address_space       = ["10.0.0.0/16"]
    location            = "eastus"
    resource_group_name = "${azurerm_resource_group.DL2terraformgroup.name}"

    tags {
        environment = "Terraform Demo"
    }
}

# Create subnet
resource "azurerm_subnet" "DL2terraformsubnet" {
    name                 = "DL2Subnet"
    resource_group_name  = "${azurerm_resource_group.DL2terraformgroup.name}"
    virtual_network_name = "${azurerm_virtual_network.DL2terraformnetwork.name}"
    address_prefix       = "10.0.1.0/24"
}

# Create public IPs
resource "azurerm_public_ip" "DL2staging_rtb_publicip" {
    name                         = "DL2staging_rtb_publicip"
    location                     = "eastus"
    resource_group_name          = "${azurerm_resource_group.DL2terraformgroup.name}"
    public_ip_address_allocation = "dynamic"

    tags {
        environment = "Terraform Demo"
    }
}

resource "azurerm_application_security_group" "staging_sellsidertb_asg" {
  name                = "staging_sellsidertb_asg"
  resource_group_name  = "${azurerm_resource_group.DL2terraformgroup.name}"
  location            = "eastus"

  tags {
    environment = "staging"
    product     = "aerserv"
    name        = "staging_sellsidertb_asg"
    service     = "azure application security group"
  }
}

output "staging_sellsidertb_asg" {
  value = "${azurerm_application_security_group.staging_sellsidertb_asg.id}"
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "DL2staging_rtb_nsg" {
    name                = "DL2staging_rtb_nsg"
    location            = "eastus"
    resource_group_name = "${azurerm_resource_group.DL2terraformgroup.name}"

    security_rule {
      name                        = "AllowSSHInbound"
      priority                    = 100
      direction                   = "Inbound"
      access                      = "Allow"
      protocol                    = "TCP"
      destination_port_range      = "22"
      source_port_range           = "*"
      source_application_security_group_ids = ["${azurerm_application_security_group.bastion_asg.id}"]
      destination_address_prefix  = "*"
    }

    security_rule {
      name                        = "AllowHTTPSInbound"
      priority                    = 101
      direction                   = "Inbound"
      access                      = "Allow"
      protocol                    = "TCP"
      source_port_range           = "*"
      destination_port_range      = "443"
      source_address_prefix       = "*"
      destination_address_prefix  = "*"
    }

    tags {
      environment = "staging"
      product     = "aerserv"
      name        = "DL2staging_rtb_nsg"
      service     = "azure network security group"
    }
}

# Create network interface
resource "azurerm_network_interface" "DL2staging_rtb_nic" {
    name                      = "DL2staging_rtb_nic"
    location                  = "eastus"
    resource_group_name       = "${azurerm_resource_group.DL2terraformgroup.name}"
    network_security_group_id = "${azurerm_network_security_group.DL2staging_rtb_nsg.id}"

    ip_configuration {
        name                          = "DL2NicConfiguration"
        subnet_id                     = "${azurerm_subnet.DL2terraformsubnet.id}"
        private_ip_address_allocation = "dynamic"
        public_ip_address_id          = "${azurerm_public_ip.DL2staging_rtb_publicip.id}"
        application_security_group_ids = ["${azurerm_application_security_group.staging_sellsidertb_asg.id}"]
    }

    tags {
        environment = "Terraform Demo"
    }
}

# Generate random text for a unique storage account name
resource "random_id" "randomId" {
    keepers = {
        # Generate a new ID only when a new resource group is defined
        resource_group = "${azurerm_resource_group.DL2terraformgroup.name}"
    }

    byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "DL2storageaccount" {
    name                        = "diag${random_id.randomId.hex}"
    resource_group_name         = "${azurerm_resource_group.DL2terraformgroup.name}"
    location                    = "eastus"
    account_tier                = "Standard"
    account_replication_type    = "LRS"

    tags {
        environment = "Terraform Demo"
    }
}

# Create virtual machine
resource "azurerm_virtual_machine" "DL2staging_rtb_vm" {
    name                  = "DL2staging_rtb_vm"
    location              = "eastus"
    resource_group_name   = "${azurerm_resource_group.DL2terraformgroup.name}"
    network_interface_ids = ["${azurerm_network_interface.DL2staging_rtb_nic.id}"]
    vm_size               = "Standard_DS1_v2"

    storage_os_disk {
        name              = "DL2RTBOsDisk"
        caching           = "ReadWrite"
        create_option     = "FromImage"
        managed_disk_type = "Premium_LRS"
    }

    storage_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "16.04.0-LTS"
        version   = "latest"
    }

    os_profile {
        computer_name  = "DL2staging-rtb-vm"
        admin_username = "azureuser"
    }

    os_profile_linux_config {
        disable_password_authentication = true
        ssh_keys {
            path     = "/home/azureuser/.ssh/authorized_keys"
            key_data = "ssh-rsa AAAAB3Nz{snip}hwhqT9h"
        }
    }

    boot_diagnostics {
        enabled = "true"
        storage_uri = "${azurerm_storage_account.DL2storageaccount.primary_blob_endpoint}"
    }

    tags {
        environment = "Terraform Demo"
    }
}

# Create public IPs
resource "azurerm_public_ip" "DL2Bastion_publicip" {
    name                         = "DL2Bastion_publicip"
    location                     = "eastus"
    resource_group_name          = "${azurerm_resource_group.DL2terraformgroup.name}"
    public_ip_address_allocation = "dynamic"

    tags {
        environment = "Terraform Demo"
    }
}

resource "azurerm_application_security_group" "bastion_asg" {
  name                = "bastion_asg"
  resource_group_name  = "${azurerm_resource_group.DL2terraformgroup.name}"
  location            = "eastus"

  tags {
    environment = "staging"
    product     = "aerserv"
    name        = "bastion_asg"
    service     = "azure application security group"
  }
}

output "bastion_asg_id" {
  value = "${azurerm_application_security_group.bastion_asg.id}"
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "DL2Bastion_nsg" {
    name                = "DL2Bastion_nsg"
    location            = "eastus"
    resource_group_name = "${azurerm_resource_group.DL2terraformgroup.name}"

    security_rule {
        name                       = "SSH"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    tags {
        environment = "Terraform Demo"
    }
}

# Create network interface
resource "azurerm_network_interface" "DL2Bastion_nic" {
    name                      = "DL2Bastion_nic"
    location                  = "eastus"
    resource_group_name       = "${azurerm_resource_group.DL2terraformgroup.name}"
    network_security_group_id = "${azurerm_network_security_group.DL2Bastion_nsg.id}"

    ip_configuration {
        name                          = "DL2NicConfiguration2"
        subnet_id                     = "${azurerm_subnet.DL2terraformsubnet.id}"
        private_ip_address_allocation = "dynamic"
        public_ip_address_id          = "${azurerm_public_ip.DL2Bastion_publicip.id}"
        application_security_group_ids = ["${azurerm_application_security_group.bastion_asg.id}"]
    }

    tags {
        environment = "Terraform Demo"
    }
}

# Create virtual machine
resource "azurerm_virtual_machine" "DL2vmBastion" {
    name                  = "DL2vmBastion"
    location              = "eastus"
    resource_group_name   = "${azurerm_resource_group.DL2terraformgroup.name}"
    network_interface_ids = ["${azurerm_network_interface.DL2Bastion_nic.id}"]
    vm_size               = "Standard_DS1_v2"

    storage_os_disk {
        name              = "DL2BastionOsDisk"
        caching           = "ReadWrite"
        create_option     = "FromImage"
        managed_disk_type = "Premium_LRS"
    }

    storage_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "16.04.0-LTS"
        version   = "latest"
    }

    os_profile {
        computer_name  = "DL2vmBastion"
        admin_username = "azureuser"
    }

    os_profile_linux_config {
        disable_password_authentication = true
        ssh_keys {
            path     = "/home/azureuser/.ssh/authorized_keys"
            key_data = "ssh-rsa AAAAB3Nz{snip}hwhqT9h"
        }
    }

    boot_diagnostics {
        enabled = "true"
        storage_uri = "${azurerm_storage_account.DL2storageaccount.primary_blob_endpoint}"
    }

    tags {
        environment = "Terraform Demo"
    }
}
