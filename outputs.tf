output "alb_dns_name" {
  value = "${module.ecs.alb_dns_name}"
}

output "repository_url" {
  value = "${module.ecs.repository_url}"
}

output "cluster_name" {
  value = "${module.ecs.cluster_name}"
}

output "service_name" {
  value = "${module.ecs.service_name}"
}