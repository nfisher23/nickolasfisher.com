resource "digitalocean_domain" "nickolasfisherdotcom" {
  name = "nickolasfisher.com"  
}

resource "digitalocean_record" "root_a" {
  domain = digitalocean_domain.nickolasfisherdotcom.name
  type   = "A"
  name   = "@"
  value  = "68.183.250.105"
}

resource "digitalocean_record" "www_a" {
  domain = digitalocean_domain.nickolasfisherdotcom.name
  type   = "A"
  name   = "www"
  value  = "68.183.250.105"
}
resource "digitalocean_record" "mx_10" {
  domain   = digitalocean_domain.nickolasfisherdotcom.name
  type     = "MX"
  name     = "@"
  value    = "mx.zoho.com."  # Note the dot at the end
  priority = 10
  ttl      = 1800  # Optional: Set an explicit TTL
}

resource "digitalocean_record" "mx_20" {
  domain   = digitalocean_domain.nickolasfisherdotcom.name
  type     = "MX"
  name     = "@"
  value    = "mx2.zoho.com."  # Note the dot at the end
  priority = 20
  ttl      = 1800  # Optional: Set an explicit TTL
}

resource "digitalocean_record" "mx_50" {
  domain   = digitalocean_domain.nickolasfisherdotcom.name
  type     = "MX"
  name     = "@"
  value    = "mx3.zoho.com."  # Note the dot at the end
  priority = 50
  ttl      = 1800  # Optional: Set an explicit TTL
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
