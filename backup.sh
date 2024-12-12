#!/bin/bash

# Bot token
# Get telegram bot token
while [[ -z "$tk" ]]; do
    echo "Bot token: "
    read -r tk
    if [[ $tk == $'\0' ]]; then
        echo "Invalid input. Token cannot be empty."
        unset tk
    fi
done

# Chat id
# Get chat id
while [[ -z "$chatid" ]]; do
    echo "Chat id: "
    read -r chatid
    if [[ $chatid == $'\0' ]]; then
        echo "Invalid input. Chat id cannot be empty."
        unset chatid
    elif [[ ! $chatid =~ ^\-?[0-9]+$ ]]; then
        echo "${chatid} is not a number."
        unset chatid
    fi
done

# Caption
# Get caption
echo "Caption (for example, your domain, to identify the database file more easily): "
read -r caption

# host
# Get host
while [[ -z "$host" ]]; do
    echo "Host: (default=127.0.0.1)"
    read -r host
    if [[ $host == $'\0' ]]; then
        host="127.0.0.1"
    fi
done

# port
# Get port
while [[ -z "$port" ]]; do
    echo "Port: (default=1433)"
    read -r port
    if [[ $port == $'\0' ]]; then
        port="1433"
    fi
done

# mssqluser
# Get mssql user
while [[ -z "$mssqluser" ]]; do
    echo "Mssql user: "
    read -r mssqluser
    if [[ $mssqluser == $'\0' ]]; then
        echo "Invalid input. mssql user cannot be empty."
        unset mssqluser
    fi
done

# mssqlpass
# Get mssql password
while [[ -z "$mssqlpass" ]]; do
    echo "Mssql password: "
    read -r mssqlpass
    if [[ $mssqlpass == $'\0' ]]; then
        echo "Invalid input. mssql password cannot be empty."
        unset mssqlpass
    fi
done


# mssqlexec
# Get mssql exec
while [[ -z "$mssqlexec" ]]; do
    echo "Mssql exec folder: (default: sqlcmd)"
    read -r mssqlexec
    if [[ $mssqlexec == $'\0' ]]; then
        mssqlexec="sqlcmd"
    fi
done


# Cronjob
# Get cronjob
while true; do
    echo "Cronjob (minutes and hours) (e.g : 30 6 or 0 12) : "
    read -r minute hour
    if [[ $minute == 0 ]] && [[ $hour == 0 ]]; then
        cron_time="* * * * *"
        break
    elif [[ $minute == 0 ]] && [[ $hour =~ ^[0-9]+$ ]] && [[ $hour -lt 24 ]]; then
        cron_time="0 */${hour} * * *"
        break
    elif [[ $hour == 0 ]] && [[ $minute =~ ^[0-9]+$ ]] && [[ $minute -lt 60 ]]; then
        cron_time="*/${minute} * * * *"
        break
    elif [[ $minute =~ ^[0-9]+$ ]] && [[ $hour =~ ^[0-9]+$ ]] && [[ $hour -lt 24 ]] && [[ $minute -lt 60 ]]; then
        cron_time="*/${minute} */${hour} * * *"
        break
    else
        echo "Invalid input, please enter a valid cronjob format (minutes and hours, e.g: 0 6 or 30 12)"
    fi
done

while [[ -z "$crontabs" ]]; do
    echo "Would you like the previous crontabs to be cleared? [y/n] : "
    read -r crontabs
    if [[ $crontabs == $'\0' ]]; then
        echo "Invalid input. Please choose y or n."
        unset crontabs
    elif [[ ! $crontabs =~ ^[yn]$ ]]; then
        echo "${crontabs} is not a valid option. Please choose y or n."
        unset crontabs
    fi
done

if [[ "$crontabs" == "y" ]]; then
# remove cronjobs
sudo crontab -l | grep -vE '/opt/mssql-backup/mssql-backup.+\.sh' | crontab -
fi

mkdir /opt/mssql-backup
mkdir /opt/mssql-backup/db-backup

# create mssql-backup.sh
    cat > "/opt/mssql-backup/mssql-backup.sh" <<EOL
#!/bin/bash

USER="$mssqluser"
PASSWORD="$mssqlpass"
HOST="$host"
PORT="$port"
MSSQL_EXEC="$mssqlexec"

DATABASES=\`\$MSSQL_EXEC -S "\$HOST,\$PORT" -U "\$USER" -C -P "\$PASSWORD" -Q "SELECT Name from sys.Databases" | grep -Ev "(----|Name|master|tempdb|model|msdb|affected\)$|\s\n|^$)"\`

for DBNAME in \$DATABASES; do
    touch "/opt/mssql-backup/db-backup/\${DBNAME}.BAK"
    chown mssql "/opt/mssql-backup/db-backup/\${DBNAME}.BAK"
    echo -n " - Backing up database \"\${DBNAME}\"... "
    \$MSSQL_EXEC -H "\$HOST,\$PORT" -U "\$USER" -C -P "\$PASSWORD" -Q "BACKUP DATABASE [\${DBNAME}] TO  DISK = '/opt/mssql-backup/db-backup/\${DBNAME}.BAK' WITH NOFORMAT, NOINIT, NAME = '\${DBNAME}-full', SKIP, NOREWIND, NOUNLOAD, STATS = 10 --with compression"
done


EOL
chmod +x /opt/mssql-backup/mssql-backup.sh

ZIP=$(cat <<EOF
bash -c "/opt/mssql-backup/mssql-backup.sh"
zip -r /opt/mssql-backup/mssql-backup.zip /opt/mssql-backup/db-backup/*
rm -rf /opt/mssql-backup/db-backup/*
EOF
)


ben_aslan="mssql backup"

trim() {
    # remove leading and trailing whitespace/lines
    local var="$*"
    # remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

IP=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')
caption="${caption}\n\n${ben_aslan}\n<code>${IP}</code>\nCreated by @ben-aslan - https://github.com/ben-aslan/mssql-backup-script"
comment=$(echo -e "$caption" | sed 's/<code>//g;s/<\/code>//g')
comment=$(trim "$comment")

# install zip
sudo apt install zip -y

# send backup to telegram
cat > "/opt/mssql-backup/mssql-backup-sender.sh" <<EOL
rm -rf /opt/mssql-backup/mssql-backup.zip
$ZIP
echo -e "$comment" | zip -z /opt/mssql-backup/mssql-backup.zip
curl -F chat_id="${chatid}" -F caption=\$'${caption}' -F parse_mode="HTML" -F document=@"/opt/mssql-backup/mssql-backup.zip" https://api.telegram.org/bot${tk}/sendDocument
EOL


# Add cronjob
{ crontab -l -u root; echo "${cron_time} /bin/bash /opt/mssql-backup/mssql-backup-sender.sh >/dev/null 2>&1"; } | crontab -u root -

# run the script
bash "/opt/mssql-backup/mssql-backup-sender.sh"

# Done
echo -e "\nDone\n"