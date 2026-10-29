####################################################################
# Health check post-déploiement
# Post-deployment health check
####################################################################

# Vérifie que le site répond bien sur le port 8080 du 1er serveur
# Checks that the site answers on port 8080 of the first server
check "health_check_http_AAP_8080" {
  data "http" "apache2_1_AAP" {
    url = "http://${aws_instance.web_server[0].public_ip}:8080"
  }

  assert {
    condition     = data.http.apache2_1_AAP.status_code == 200
    error_message = "${data.http.apache2_1_AAP.url} returned an unhealthy status code"
  }
}
