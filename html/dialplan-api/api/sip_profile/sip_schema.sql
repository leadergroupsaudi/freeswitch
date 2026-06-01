-- =========================
-- SIP PROFILES TABLE
-- =========================
CREATE TABLE IF NOT EXISTS sip_profiles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    filename VARCHAR(255) NOT NULL,
    description VARCHAR(255) DEFAULT '',
    is_custom TINYINT(1) DEFAULT 0,
    enabled TINYINT(1) DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- =========================
-- SIP PROFILE PARAMETERS
-- =========================
CREATE TABLE IF NOT EXISTS sip_profile_params (
    id INT AUTO_INCREMENT PRIMARY KEY,
    profile_id INT NOT NULL,
    param_name VARCHAR(150) NOT NULL,
    param_value TEXT NOT NULL,
    description VARCHAR(500) DEFAULT '',
    category VARCHAR(50) DEFAULT 'general',
    is_sensitive TINYINT(1) DEFAULT 0,
    editable TINYINT(1) DEFAULT 1,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    updated_by VARCHAR(100) DEFAULT 'admin',
    FOREIGN KEY (profile_id) REFERENCES sip_profiles(id) ON DELETE CASCADE,
    UNIQUE KEY unique_profile_param (profile_id, param_name)
);

-- =========================
-- DEFAULT PROFILES
-- =========================
INSERT IGNORE INTO sip_profiles (name, filename, description, is_custom)
VALUES
('internal', 'sip_profiles/internal.xml', 'Internal SIP profile', 0),
('external', 'sip_profiles/external.xml', 'External SIP profile', 0);

-- =========================
-- GET IDS
-- =========================
SET @int_id = (SELECT id FROM sip_profiles WHERE name='internal');
SET @ext_id = (SELECT id FROM sip_profiles WHERE name='external');

-- =========================
-- INTERNAL PROFILE PARAMS
-- =========================
INSERT IGNORE INTO sip_profile_params
(profile_id,param_name,param_value,description,category,is_sensitive,editable)
VALUES
(@int_id,'sip-ip','$${local_ip_v4}','SIP IP','network',0,1),
(@int_id,'sip-port','5060','SIP Port','network',0,1),
(@int_id,'rtp-ip','$${local_ip_v4}','RTP IP','network',0,1),
(@int_id,'ext-sip-ip','$${external_sip_ip}','External SIP IP','network',0,1),
(@int_id,'ext-rtp-ip','$${external_rtp_ip}','External RTP IP','network',0,1),
(@int_id,'codec-prefs','PCMU,PCMA,G722','Codecs','codecs',0,1),
(@int_id,'dtmf-type','rfc2833','DTMF type','dtmf',0,1),
(@int_id,'context','default','Dialplan context','general',0,1),
(@int_id,'auth-calls','true','Require auth','registration',0,1),
(@int_id,'debug','0','Debug level','general',0,1);

-- =========================
-- EXTERNAL PROFILE PARAMS
-- =========================
INSERT IGNORE INTO sip_profile_params
(profile_id,param_name,param_value,description,category,is_sensitive,editable)
VALUES
(@ext_id,'sip-ip','$${local_ip_v4}','SIP IP','network',0,1),
(@ext_id,'sip-port','5080','SIP Port','network',0,1),
(@ext_id,'codec-prefs','PCMU,PCMA','Codecs','codecs',0,1),
(@ext_id,'context','public','Dialplan context','general',0,1),
(@ext_id,'auth-calls','false','Auth required','registration',0,1),
(@ext_id,'debug','0','Debug level','general',0,1);

-- =========================
-- VERIFY
-- =========================
SELECT p.name, COUNT(pp.id) AS params
FROM sip_profiles p
LEFT JOIN sip_profile_params pp ON pp.profile_id = p.id
GROUP BY p.name;
