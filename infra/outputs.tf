output "public_ip" {
  description = "Public IP of the chat application host."
  value       = aws_instance.chat.public_ip
}

output "application_url" {
  description = "Public URL of the deployed chat application."
  value       = "http://${aws_instance.chat.public_ip}"
}
