resource "null_resource" "run_shell_script" {
  provisioner "local-exec" {
    command = "chmod +x pod.sh && ./pod.sh <aws_access_key> <aws_secret_key>"
    interpreter = ["/bin/bash", "-c"]
  }
}