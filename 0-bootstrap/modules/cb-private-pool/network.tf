/**
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

locals {
  peered_ip_range = var.private_worker_pool.enable_network_peering ? "${google_compute_global_address.worker_pool_range[0].address}/${google_compute_global_address.worker_pool_range[0].prefix_length}" : ""
}

module "peered_network" {
  source  = "terraform-google-modules/network/google"
  version = "~> 5.2"
  count   = var.private_worker_pool.create_peered_network ? 1 : 0

  project_id                             = var.project_id
  network_name                           = local.network_name
  delete_default_internet_gateway_routes = "true"

  subnets = [
    {
      subnet_name           = "sb-peered"
      subnet_ip             = var.private_worker_pool.peered_network_subnet_ip
      subnet_region         = var.private_worker_pool.region
      subnet_private_access = "true"
      subnet_flow_logs      = "true"
      description           = "Peered subnet for Cloud Build private pool"
    }
  ]

}

resource "google_compute_global_address" "worker_pool_range" {
  count = var.private_worker_pool.enable_network_peering ? 1 : 0

  name          = "ga-worker-pool-range-vpc-peering"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = var.private_worker_pool.peering_address
  prefix_length = var.private_worker_pool.peering_prefix_length
  network       = local.peered_network_id
}

resource "google_service_networking_connection" "worker_pool_conn" {
  count = var.private_worker_pool.enable_network_peering ? 1 : 0

  network                 = local.peered_network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.worker_pool_range[0].name]
}

resource "google_compute_network_peering_routes_config" "peering_routes" {
  count = var.private_worker_pool.enable_network_peering ? 1 : 0

  project = var.project_id
  peering = google_service_networking_connection.worker_pool_conn[0].peering
  network = local.peered_network_name

  import_custom_routes = true
  export_custom_routes = true
}

module "firewall_rules" {
  source  = "terraform-google-modules/network/google//modules/firewall-rules"
  version = "~> 5.2"
  count   = var.private_worker_pool.enable_network_peering ? 1 : 0

  project_id   = var.project_id
  network_name = local.peered_network_id

  rules = [{
    name                    = "allow-servicenetworking-ingress"
    description             = "allow ingres from the IPs configured for service networking"
    direction               = "INGRESS"
    priority                = 100
    source_tags             = null
    source_service_accounts = null
    target_tags             = null
    target_service_accounts = null

    ranges = [local.peered_ip_range]

    allow = [{
      protocol = "all"
      ports    = null
    }]

    deny = []

    log_config = {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }]
}