resource "digitalocean_domain" "nickolasfisherdotcom" {
  name = "nickolasfisher.com"  
}

resource "digitalocean_record" "root_a1" {
  domain = digitalocean_domain.nickolasfisherdotcom.name
  type   = "A"
  name   = "@"
  value  = "185.199.108.153"
  ttl      = 60  # Optional: Set an explicit TTL
}

resource "digitalocean_record" "root_a2" {
  domain = digitalocean_domain.nickolasfisherdotcom.name
  type   = "A"
  name   = "@"
  value  = "185.199.109.153"
  ttl      = 60  # Optional: Set an explicit TTL
}

resource "digitalocean_record" "root_a3" {
  domain = digitalocean_domain.nickolasfisherdotcom.name
  type   = "A"
  name   = "@"
  value  = "185.199.110.153"
  ttl      = 60  # Optional: Set an explicit TTL
}

resource "digitalocean_record" "root_a4" {
  domain = digitalocean_domain.nickolasfisherdotcom.name
  type   = "A"
  name   = "@"
  value  = "185.199.111.153"
  ttl      = 60  # Optional: Set an explicit TTL
}

# CNAME record for www subdomain
resource "digitalocean_record" "www_cname" {
  domain = digitalocean_domain.nickolasfisherdotcom.name
  type   = "CNAME"
  name   = "www"
  value  = "nfisher23.github.io."
  ttl      = 60  # Optional: Set an explicit TTL
}

resource "digitalocean_record" "mx_10" {
  domain   = digitalocean_domain.nickolasfisherdotcom.name
  type     = "MX"
  name     = "@"
  value    = "mx.zoho.com."  # Note the dot at the end
  priority = 10
  ttl      = 60  # Optional: Set an explicit TTL
}

resource "digitalocean_record" "mx_20" {
  domain   = digitalocean_domain.nickolasfisherdotcom.name
  type     = "MX"
  name     = "@"
  value    = "mx2.zoho.com."  # Note the dot at the end
  priority = 20
  ttl      = 60  # Optional: Set an explicit TTL
}

resource "digitalocean_record" "mx_50" {
  domain   = digitalocean_domain.nickolasfisherdotcom.name
  type     = "MX"
  name     = "@"
  value    = "mx3.zoho.com."  # Note the dot at the end
  priority = 50
  ttl      = 60  # Optional: Set an explicit TTL
}

resource "digitalocean_record" "txt_zoho_verification" {
  domain = digitalocean_domain.nickolasfisherdotcom.name
  type   = "TXT"
  name   = "@"
  value  = "zoho-verification=zb94184910.zmverify.zoho.com"
}

resource "digitalocean_record" "txt_spf" {
  domain = digitalocean_domain.nickolasfisherdotcom.name
  type   = "TXT"
  name   = "@"
  value  = "v=spf1 include:zohomail.com ~all"
}

resource "digitalocean_record" "txt_dkim" {
  domain = digitalocean_domain.nickolasfisherdotcom.name
  type   = "TXT"
  name   = "zmail._domainkey"
  value  = "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCxPzXMsIUke3rUp3kfUxmqHGyfJKaG2gDn9+7bHR+VTvfVMALg32vJKumuR1hCZ/9ZUwAMxWDPZkHOxMFJBFPCDQTklydVHx3jLM5Pr4dx0lRMC+cMXP1P8545tTahOAQZKyuneJfCI3yQgbwtvc04m8z+6coNnM0hzCPdBXTwIDAQAB"
}
