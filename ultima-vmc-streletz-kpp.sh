#!/bin/bash

########### ---------> Удаление сгенерированных файлов при неудачной отработке скрипта ???

########### ---------> сюда чот нужно было написать как напоминалку но забыл

API_KEY=""
ENDPOINT=""
OUTPUT_LICENCE_FILE="/home/ultima-vmc/Neyross/ultima-vmc/licence"
NEUROTEC_ACTIVATION_DIR="/opt/ultima-activation"

exec > $NEUROTEC_ACTIVATION_DIR/ultima-activation.log

until nslookup google.com > /dev/null
do
echo "No internet connection available... Waiting for internet connection..."
sleep 1
done

until nslookup $ENDPOINT > /dev/null
do
echo "domain is not responding... Waiting for domain..."
sleep 1
done

function generate_hid {
uuid=$(echo $(dmidecode -t 1 | grep "UUID") | sed -e "s/^UUID: //" | xargs)
processor_id=$(echo $(dmidecode -t 4 | grep "ID:") | sed -e "s/^ID: //" | xargs)

serial_numbers=$(dmidecode -t 17 | grep "Serial Number:")

not_found_serial_number_lable="__NOT_FOUND__"
found_serial_number=$not_found_serial_number_lable

last_ifs=$IFS
IFS='
'
array=($serial_numbers)
array_length=${#array[@]}

for i in ${array[@]}
do
    serial_number=$(echo ${i} | sed -e "s/Serial Number: //" | xargs)
    if [[ $serial_number != "[Empty]" ]]
    then
        found_serial_number=$serial_number
        break
    fi
done

IFS=$last_ifs

if [[ $found_serial_number == $not_found_serial_number_lable ]]
then
    found_serial_number="0"
fi

if [[ $processor_id == "" ]]
then
    processor_id="0"
fi

if [[ $uuid == "" ]]
then
    uuid="0"
fi

zeroCount=0
unnamed=($found_serial_number, $processor_id,  $uuid)
for i in ${unnamed[@]}
do
        if [ i == "0" ]
        then
                zeroCount=zeroCount+1
        fi
done
if [ $zeroCount -gt 1 ]
then
        echo "Can't generate HID, exiting..."
        exit 1
fi

echo -n "${uuid}|${found_serial_number}|${processor_id}" | md5sum | awk '{print toupper($0)}' | cat | sed 's/.$//' | xargs
}

HID=$(generate_hid)

LIC_NAME="Streletz-KPP-$HID"

echo "performing licence generation; HID = $HID"

FULL_JSON=$(curl -X POST http://$ENDPOINT/api/generate/\?hid\=$HID\&name\=$LIC_NAME\&apiKey\=$API_KEY\&withNeurotec\=true)

echo "FULL JSON: $FULL_JSON"

echo "done; created new customer; full json is $FULL_JSON. Parsing id..."

ID=$(echo $FULL_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")

NEUROTEC_KEYS=$(echo $FULL_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['licence']['neurotec:licenceKey'])")

echo "done; new customer id = $ID, neurotec keys = $NEUROTEC_KEYS; downloading licence and saving to file $OUTPUT_LICENCE_FILE..."

curl http://$ENDPOINT/api/licence/\?customerId\=$ID --output $OUTPUT_LICENCE_FILE

echo "done; generating Neurotec serial numbers..."

echo $NEUROTEC_KEYS | awk '{print $1}' | rev | cut -c 2- | rev > $NEUROTEC_ACTIVATION_DIR/neurotec-sn1.txt

echo $NEUROTEC_KEYS | awk '{print $2}' > $NEUROTEC_ACTIVATION_DIR/neurotec-sn2.txt

echo "done; generating Neurotech id-files..."

cd $NEUROTEC_ACTIVATION_DIR

$NEUROTEC_ACTIVATION_DIR/id_gen neurotec-sn1.txt neurotechnology1.id

$NEUROTEC_ACTIVATION_DIR/id_gen neurotec-sn2.txt neurotechnology2.id

echo "done; activating Neurotech licences..."

$NEUROTEC_ACTIVATION_DIR/license_activation neurotec-sn1.txt -o licence1.lic

$NEUROTEC_ACTIVATION_DIR/license_activation neurotec-sn2.txt -o licence2.lic

mv $NEUROTEC_ACTIVATION_DIR/licence1.lic $NEUROTEC_ACTIVATION_DIR/licence2.lic /home/ultima-vmc/Neyross/ultima-vmc/resources/neurotech-licence/

echo "Starting ultima-vmc service..."

systemctl enable ultima-vmc

systemctl start ultima-vmc

systemctl disable ultima-vmc-streletz-kpp

reboot

echo "done"
