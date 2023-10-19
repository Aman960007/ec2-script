resource "null_resource" "run_shell_script" {
  provisioner "local-exec" {
    command = "chmod +x pod.sh && ./pod.sh"
    interpreter = ["/bin/bash", "-c"]
  }
}