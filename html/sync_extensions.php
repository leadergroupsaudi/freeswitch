python3 -c "
content = '''<?php
error_reporting(E_ALL);
ini_set(\"display_errors\", 1);

\$conn      = new mysqli(\"localhost\", \"phpuser\", \"php123\", \"pbx_user\");
\$directory = \"/usr/local/freeswitch-automax-instance/etc/freeswitch/directory/leaderfs.axionic.io/\";

if (\$conn->connect_error) {
    die(\"DB connection failed: \" . \$conn->connect_error);
}

\$files    = glob(\$directory . \"*.xml\");
\$inserted = 0;
\$skipped  = 0;

foreach (\$files as \$file) {
    \$xml = simplexml_load_file(\$file);
    if (!\$xml) continue;

    \$extension = (string)\$xml->user[\"id\"];
    if (!preg_match(\"/^\\\d+\$/\", \$extension)) continue;

    \$password = \"\";
    foreach (\$xml->user->params->param as \$param) {
        if ((string)\$param[\"name\"] === \"password\") {
            \$password = (string)\$param[\"value\"];
            break;
        }
    }

    \$name = \"Extension \" . \$extension;
    foreach (\$xml->user->variables->variable as \$variable) {
        if ((string)\$variable[\"name\"] === \"effective_caller_id_name\") {
            \$name = (string)\$variable[\"value\"];
            break;
        }
    }

    \$stmt = \$conn->prepare(\"INSERT IGNORE INTO extensions (extension, password, name) VALUES (?, ?, ?)\");
    \$stmt->bind_param(\"sss\", \$extension, \$password, \$name);
    \$stmt->execute();

    if (\$stmt->affected_rows > 0) {
        \$inserted++;
        echo \"Inserted: \" . \$extension . \" - \" . \$name . \"\\n\";
    } else {
        \$skipped++;
        echo \"Skipped: \" . \$extension . \"\\n\";
    }
    \$stmt->close();
}

echo \"\\nTotal inserted : \" . \$inserted . \"\\n\";
echo \"Total skipped  : \" . \$skipped . \"\\n\";
'''
with open('/var/www/html/sync_extensions.php', 'w') as f:
    f.write(content)
print('File written successfully')
"
