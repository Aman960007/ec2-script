resource "null_resource" "run_shell_script" {
  provisioner "local-exec" {
    command = "chmod +x pod.sh && ./pod.sh AKIAXBOVP6PEMWQX6WIC mMHv5rklWru2jhDECxu7av+ps3wKZS2x7I+dt8Tj"
    interpreter = ["/bin/bash", "-c"]
  }
}