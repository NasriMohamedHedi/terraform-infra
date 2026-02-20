output "eks_kubeconfig" {
  description = "Kubeconfig for the EKS cluster (auto-generated from module.eks outputs)"
  value = templatefile("${path.module}/kubeconfig.tpl", {
    cluster_name = try(module.eks["eks"].cluster_name, "")
    endpoint     = try(module.eks["eks"].cluster_endpoint, "")
    certificate  = try(module.eks["eks"].cluster_certificate_authority_data, "")
  })

  sensitive = true
}

