#!/bin/bash

# Descripcion
TITULO="Solución VoIP con Asterisk y Linphone"
CURSO="Centros de Datos, 2025/26"
DIR_BASE_POR_DEFECTO=$HOME/CDA2526

URL_BASE=http://cda.drordas.info
DIR_BASE=${DIR_BASE:-$DIR_BASE_POR_DEFECTO}
DIR_VARLIB=/var/lib/CDA2526

HOST_IFACE=$(ip route | awk '/default/ {print $5; exit}')

VBOX_ISO_VERSION="7.0.16" 
GUEST_ADDITIONS_ISO="$DIR_BASE/VBoxGuestAdditions_$VBOX_ISO_VERSION.iso"
URL_GUEST_ADDITIONS="https://download.virtualbox.org/virtualbox/$VBOX_ISO_VERSION/VBoxGuestAdditions_$VBOX_ISO_VERSION.iso"


es_imagen_registrada() {
    local IMAGEN=$1
    
    if VBoxManage list hdds | grep -q $IMAGEN ; then
        true
    else
        false
    fi
}

registrar_imagen(){
    local DIR_BASE=$1
    local IMAGEN=$2
    local TIPO=$3
    
    if ! VBoxManage list vms | grep -q CDA_NO_BORRAR ; then
        VBoxManage createvm  --name CDA_NO_BORRAR --basefolder "$DIR_BASE" --register
        VBoxManage storagectl CDA_NO_BORRAR --name CDA_NO_BORRAR_storage  --add sata  --portcount 4
    fi
    VBoxManage -q storageattach CDA_NO_BORRAR --storagectl CDA_NO_BORRAR_storage --port 0 --device 0 --type hdd --medium "$IMAGEN" --mtype normal
    VBoxManage -q storageattach CDA_NO_BORRAR --storagectl CDA_NO_BORRAR_storage --port 0 --device 0 --type hdd --medium none 2>/dev/null || true
    VBoxManage modifymedium "$IMAGEN" --type $TIPO            
}


registrar_imagenes() {
    local DIR_BASE=$1
    local IMAGEN_BASE=$2
    local IMAGEN_SWAP=$3

    if ! es_imagen_registrada $IMAGEN_BASE
    then
        registrar_imagen $DIR_BASE  $IMAGEN_BASE "multiattach"
    fi
    
    if ! es_imagen_registrada $IMAGEN_SWAP
    then
        registrar_imagen $DIR_BASE $IMAGEN_SWAP "immutable"    
    fi
    
    
}

preparar_imagen() {
  local NOMBRE_IMAGEN=$1
  local URL_BASE_ORIGEN=$2
  local DIR_BASE_DESTINO=$3
  
  local URL_ORIGEN=$URL_BASE_ORIGEN/$1.vdi.zip  
  local IMAGEN_DESTINO=$DIR_BASE_DESTINO/$1.vdi
  
  if [ ! -e $IMAGEN_DESTINO ];
  then
     if [ ! -e $DIR_BASE_DESTINO/$1.vdi.zip ];
     then
        echo "Descargando imagen $URL_ORIGEN ... "
        cd $DIR_BASE_DESTINO
        wget --continue $URL_ORIGEN
     fi
     echo "Descomprimiendo imagen $IMAGEN_DESTINO ... "
     unzip $1.vdi.zip
     rm $1.vdi.zip
  fi
}

preparar_guest_additions() {
  local IMAGEN_DESTINO=$GUEST_ADDITIONS_ISO
  local URL_ORIGEN=$URL_GUEST_ADDITIONS
  local DIR_BASE_DESTINO=$DIR_BASE

  if [ ! -e "$IMAGEN_DESTINO" ]; then
     echo "Descargando ISO de Guest Additions ($VBOX_ISO_VERSION) desde $URL_ORIGEN ... "
     # Nos aseguramos de que el directorio base exista antes de descargar
     mkdir -p "$DIR_BASE_DESTINO"
     cd "$DIR_BASE_DESTINO"
     # Descargar y renombrar el archivo si es necesario. Usamos -O para guardar con el nombre original.
     wget --continue "$URL_ORIGEN" -O "$IMAGEN_DESTINO"

     if [ $? -ne 0 ]; then
        echo "ERROR: Falló la descarga de VBoxGuestAdditions.iso. Verifique la versión y la URL."
        exit 1
     fi
  fi
}


# Crear directorio base
if [ ! -e $DIR_BASE ];
then
  echo "Creando directorio $DIR_BASE ..."
  mkdir -p $DIR_BASE
fi


# Descargar imagenes base
IMAGEN_BASE=$DIR_VARLIB/base_cda.vdi
if [ ! -e $IMAGEN_BASE ];
then
    IMAGEN_BASE=$DIR_BASE/base_cda.vdi
    preparar_imagen "base_cda" $URL_BASE  $DIR_BASE
fi

IMAGEN_SWAP=$DIR_VARLIB/swap1GB.vdi
if [ ! -e $IMAGEN_SWAP ];
then
    IMAGEN_SWAP=$DIR_BASE/swap1GB.vdi
    preparar_imagen "swap1GB"     $URL_BASE  $DIR_BASE
fi

registrar_imagenes $DIR_BASE $IMAGEN_BASE $IMAGEN_SWAP

# PREPARACIÓN AUTOMÁTICA DE GUEST ADDITIONS
preparar_guest_additions

# Leer ID
ID=CDA
DIALOG=`which dialog`

if [ ! $DIALOG ]; 
then
   echo "$TITULO -- $CURSO"
   echo -n "Introducir un identificador único (sin espacios) [+ ENTER]: "
   read ID;
else
  $DIALOG --title "$TITULO" --backtitle "$CURSO" \
          --inputbox "Introducir un identificador único (sin espacios): " 8 50  2> /tmp/ID.txt
  ID=`head -1 /tmp/ID.txt`
fi

# =========================================================================
# Definición del contenido del archivo cdr.conf de Asterisk
# El script de aprovisionamiento en la MV deberá leer esta variable
# para escribir el archivo /etc/asterisk/cdr.conf.
# =========================================================================
CDR_CONF_CONTENT=$(cat <<'EOF_CDR_CONF'
[general]

[csv]
usegmtime=yes    ; log date/time in GMT.  Default is "no"
loguniqueid=yes  ; log uniqueid.  Default is "no"
loguserfield=yes ; log user field.  Default is "no"
accountlogs=yes  ; create separate log file for each account code. Default is "yes"
;newcdrcolumns=yes ; Enable logging of post-1.8 CDR columns (peeraccount, linkedid, sequence).
                 ; Default is "no".

;[radius]
;usegmtime=yes    ; log date/time in GMT
;loguniqueid=yes  ; log uniqueid
;loguserfield=yes ; log user field
; Set this to the location of the radiusclient-ng configuration file
; The default is /etc/radiusclient-ng/radiusclient.conf
;radiuscfg => /usr/local/etc/radiusclient-ng/radiusclient.conf
radiuscfg => /etc/radcli/radiusclient.conf
EOF_CDR_CONF
)

# =========================================================================
# Definición del contenido del archivo cel.conf de Asterisk
# El script de aprovisionamiento en la MV deberá leer esta variable
# para escribir el archivo /etc/asterisk/cel.conf.
# =========================================================================
CEL_CONF_CONTENT=$(cat <<'EOF_CEL_CONF'
[general]

apps=dial,park
events=APP_START,CHAN_START,CHAN_END,ANSWER,HANGUP,BRIDGE_ENTER,BRIDGE_EXIT
[manager]

; AMI Backend Activation
;
; Use the 'enable' keyword to turn CEL logging to the Asterisk Manager Interface
; on or off.
;
; Accepted values: yes and no
; Default value:   no
;enabled=yes

; Use 'show_user_defined' to put "USER_DEFINED" in the EventName header,
; instead of (by default) just putting the user defined event name there.
; When enabled the UserDefType header is added for user defined events to
; provide the user defined event name.
;
;show_user_defined=yes

;
; RADIUS CEL Backend
;
[radius]
;
; Log date/time in GMT
;usegmtime=yes
;
; Set this to the location of the radiusclient-ng configuration file
; The default is /etc/radiusclient-ng/radiusclient.conf
;radiuscfg => /usr/local/etc/radiusclient-ng/radiusclient.conf
radiuscfg => /etc/radcli/radiusclient.conf
EOF_CEL_CONF
)

# =========================================================================
# Definición del contenido del archivo sip.conf de Asterisk
# El script de aprovisionamiento en la MV deberá leer esta variable
# para escribir el archivo /etc/asterisk/sip.conf.
# =========================================================================
SIP_CONF_CONTENT=$(cat <<'EOF_SIP_CONF'
[general]
context=public
realm=asterisk
allowoverlap=no
localnet=192.168.100.0/24
udpbindaddr=0.0.0.0
tcpenable=no
tcpbindaddr=0.0.0.0
transport=udp
srvlookup=yes
qualify=yes
language=es
disallow=all
allow=alaw, ulaw

[authentication]
[basic-options](!)
    dtmfmode=rfc2833
    context=from-office
    type=friend
[natted-phone](!,basic-options)
    directmedia=no
    host=dynamic
[public-phone](!,basic-options)
    directmedia=yes
[my-codecs](!)
    disallow=all
    allow=ilbc
    allow=g729
    allow=gsm
    allow=g723
    allow=ulaw
[ulaw-phone](!)
    disallow=all
    allow=ulaw


[usuario](!)
type=friend
host=dynamic
context=servidorCDA

;Extension 101
[ext101](usuario)
secret=cda1
port=5060

;Extension 102
[ext102](usuario)
secret=cda2
port=5060
EOF_SIP_CONF
)

# =========================================================================
# Definición del contenido del archivo extensions.conf de Asterisk
# El script de aprovisionamiento en la MV deberá leer esta variable
# para escribir el archivo /etc/asterisk/extensions.conf.
# =========================================================================
EXTENSIONS_CONF_CONTENT=$(cat <<'EOF_EXTENSIONS_CONF'
[general]
[globals]
[servidorCDA]
;Extension 101 Manu
exten => 101,1,Dial(SIP/ext101,20)
exten => 101,n,GotoIf($["${DIALSTATUS}"="BUSY"]?busy:unavail)
exten => 101,n(unavail),VoiceMail(101@default,u)
exten => 101,n,Hangup()
exten => 101,n(busy),VoiceMail(101@default,b)
exten => 101,n,Hangup()
;Extension 102 Ana
exten => 102,1,Dial(SIP/ext102)
exten => 102,n,GotoIf($["${DIALSTATUS}"="BUSY"]?busy:unavail)
exten => 102,n(unavail),VoiceMail(102@default,u)
exten => 102,n,Hangup()
exten => 102,n(busy),VoiceMail(102@default,b)
exten => 102,n,Hangup()
;Acceso al Voice Mail
exten => 8500,1,Answer()
exten => 8500,n,Wait(1)
exten => 8500,n,VoiceMailMain(${CALLERID(num)}@default)
exten => 8500,n,Hangup()

; **CRÍTICO:** Extensión de finalización de llamada (h)
exten => h,1,Hangup()
EOF_EXTENSIONS_CONF
)

# =========================================================================
# Definición del contenido del archivo voicemail.conf de Asterisk
# =========================================================================
VOICEMAIL_CONF_CONTENT=$(cat <<'EOF_VOICEMAIL_CONF'
[general]
format=wav
serveremail=asterisk
serveremail=asterisk@linux-support.net
attach=yes
maxmsg=100
maxsecs=300
minsecs=3
maxgreet=60
skipms=3000
maxsilence=10
silencethreshold=128
maxlogins=3
moveheard=yes
userscontext=default
directoryintro=dir-intro
charset=ISO-8859-1
pbxskip=yes
fromstring=VozToVoice
usedirectory=yes
emaildateformat=%A, %B %d, %Y at %r
pagerdateformat=%A, %B %d, %Y at %r
mailcmd=/usr/sbin/sendmail -t
attach=yes
attachfmt=wav
saycid=no
sayduration=no
saydurationm=2
dialout=phones
sendvoicemail=yes
review=yes
envelope=no
forcename=yes
forcegreetings=no
hidefromdir=yes
tempgreetwarn=yes
listen-control-forward-key=#
listen-control-reverse-key=*
listen-control-pause-key=0
listen-control-restart-key=2
listen-control-stop-key=13456789
backupdeleted=100
language=es

[zonemessages]
eastern=America/New_York|'vm-received' Q 'digits/at' IMp
central=America/Chicago|'vm-received' Q 'digits/at' IMp
central24=America/Chicago|'vm-received' q 'digits/at' H N 'hours'
military=Zulu|'vm-received' q 'digits/at' H N 'hours' 'phonetic/z_p'
european=Europe/Copenhagen|'vm-received' a d b 'digits/at' HM

[default]
1234 => 4242,Example Mailbox,root@localhost
# Buzón 101 con idioma español forzado
101 => 1234,Manu,mcperez23@esei.uvigo.es,,envelope=no|saycid=no|lang=es
# Buzón 102 con idioma español forzado
102 => 4321,Ana,aalopez23@eseo.uvigo.es,,envelope=no|saycid=no|lang=es

[myaliases]
1234@devices => 1234@default

[other]
1234 => 5678,Company2 User,root@localhost
EOF_VOICEMAIL_CONF
)

MV_ASTERISK="ASTERISK_$ID"
if ! VBoxManage list vms | grep -q "$MV_ASTERISK"; then

  # Solo 1 vez
  VBoxManage createvm  --name $MV_ASTERISK --basefolder "$DIR_BASE" --register  --ostype Debian_64 

  VBoxManage storagectl $MV_ASTERISK --name ${MV_ASTERISK}_storage  --add sata --portcount 8 2>/dev/null || true
  VBoxManage storagectl $MV_ASTERISK --name IDE --add ide 2>/dev/null || true
  VBoxManage storageattach $MV_ASTERISK --storagectl ${MV_ASTERISK}_storage --port 0 --device 0 --type hdd --medium "$IMAGEN_BASE" --mtype multiattach 
  VBoxManage storageattach $MV_ASTERISK --storagectl ${MV_ASTERISK}_storage --port 1 --device 0 --type hdd --medium "$IMAGEN_SWAP" --mtype immutable 
    VBoxManage storageattach $MV_ASTERISK --storagectl IDE --port 1 --device 0 --type dvddrive --medium none 2>/dev/null || true

  VBoxManage modifyvm $MV_ASTERISK --cpus 2 --memory 512 --pae on --vram 16 --graphicscontroller vmsvga
  # NIC1: Red Interna (IntNet) para VoIP
  VBoxManage modifyvm $MV_ASTERISK --nic1 intnet --intnet1 vlan1 --macaddress1 080027111111 --cableconnected1 on --nictype1 82540EM
  # NIC2: Adaptador Puenteado (Bridged) para acceso externo
  VBoxManage modifyvm $MV_ASTERISK --nic2 bridged --bridgeadapter2 "$HOST_IFACE" --macaddress2 080027111101 --cableconnected2 on --nictype2 82540EM

  # El Port Forwarding se elimina en Bridged
  # VBoxManage modifyvm $MV_ASTERISK --nat-pf2 "guestssh,tcp,,2222,,22"
  VBoxManage modifyvm $MV_ASTERISK --clipboard-mode bidirectional
  
  # --- Configuración de Red e Hosts
  VBoxManage guestproperty set $MV_ASTERISK /DSBOX/num_interfaces 2
  VBoxManage guestproperty set $MV_ASTERISK /DSBOX/eth/0/type static
  VBoxManage guestproperty set $MV_ASTERISK /DSBOX/eth/0/address 192.168.100.11
  VBoxManage guestproperty set $MV_ASTERISK /DSBOX/eth/0/netmask 24
  # eth/1 en Bridged debe configurarse con DHCP
  VBoxManage guestproperty set $MV_ASTERISK /DSBOX/eth/1/type dhcp
  # VBoxManage guestproperty set $MV_ASTERISK /DSBOX/eth/1/address 10.0.3.15 # Se elimina la IP estática en Bridged
  VBoxManage guestproperty set $MV_ASTERISK /DSBOX/eth/1/netmask 24
  # El gateway y nameserver se obtendrán por DHCP, pero se mantienen como reserva para la MV
  VBoxManage guestproperty set $MV_ASTERISK /DSBOX/default_gateway 10.0.3.2 
  VBoxManage guestproperty set $MV_ASTERISK /DSBOX/default_nameserver 8.8.8.8
  VBoxManage guestproperty set $MV_ASTERISK /DSBOX/host_name ASTERISK.cda.net
  VBoxManage guestproperty set $MV_ASTERISK /DSBOX/etc_hosts_dump "ASTERISK.cda.net:192.168.100.11,cliente1.cda.net:192.168.100.22,cliente2.cda.net:192.168.100.33"


  # --- Configuración del Servidor Asterisk (VOIP) ---
  # La IP de Asterisk será la misma que eth/0 (192.168.100.11)
  VBoxManage guestproperty set $MV_ASTERISK /DSBOX/voip/type asterisk
  VBoxManage guestproperty set $MV_ASTERISK /DSBOX/voip/ip_address 192.168.100.11
  VBoxManage guestproperty set $MV_ASTERISK /DSBOX/voip/rtp_start 10000
  VBoxManage guestproperty set $MV_ASTERISK /DSBOX/voip/rtp_end 20000
  VBoxManage guestproperty set $MV_ASTERISK /DSBOX/voip/sip_port 5060
  # ---------------------------------------------------

  # --- Archivos de Configuración Asterisk ---
  VBoxManage guestproperty set $MV_ASTERISK /DSBOX/asterisk/cdr_conf_dump "$CDR_CONF_CONTENT"
  VBoxManage guestproperty set $MV_ASTERISK /DSBOX/asterisk/cel_conf_dump "$CEL_CONF_CONTENT"
  VBoxManage guestproperty set $MV_ASTERISK /DSBOX/asterisk/sip_conf_dump "$SIP_CONF_CONTENT"
  VBoxManage guestproperty set $MV_ASTERISK /DSBOX/asterisk/extensions_conf_dump "$EXTENSIONS_CONF_CONTENT"
  # ------------------------------------------
  
fi


MV_CLIENTE1="CLIENTE1_$ID"
if ! VBoxManage list vms | grep -q "$MV_CLIENTE1"; then
  # Solo 1 vez
  VBoxManage createvm  --name $MV_CLIENTE1 --basefolder "$DIR_BASE" --register --ostype Debian_64 

      VBoxManage storagectl $MV_CLIENTE1 --name ${MV_CLIENTE1}_storage  --add sata --portcount 4  2>/dev/null || true
  VBoxManage storagectl $MV_CLIENTE1 --name IDE --add ide 2>/dev/null || true
  VBoxManage storageattach $MV_CLIENTE1 --storagectl ${MV_CLIENTE1}_storage --port 0 --device 0 --type hdd --medium "$IMAGEN_BASE" --mtype multiattach 
  VBoxManage storageattach $MV_CLIENTE1 --storagectl ${MV_CLIENTE1}_storage --port 1 --device 0 --type hdd --medium "$IMAGEN_SWAP" --mtype immutable 
    VBoxManage storageattach $MV_CLIENTE1 --storagectl IDE --port 1 --device 0 --type dvddrive --medium none 2>/dev/null || true

  VBoxManage modifyvm $MV_CLIENTE1 --cpus 2 --memory 512 --pae on --vram 16 --graphicscontroller vmsvga
  VBoxManage modifyvm $MV_CLIENTE1 --nic1 intnet --intnet1 vlan1 --macaddress1 080027222222 --cableconnected1 on --nictype1 82540EM
  VBoxManage modifyvm $MV_CLIENTE1 --nic2 nat --macaddress2 080027222202 --cableconnected2 on --nictype2 82540EM

  VBoxManage modifyvm $MV_CLIENTE1 --nat-pf2 "guestssh,tcp,,2223,,22"
  VBoxManage modifyvm $MV_CLIENTE1 --clipboard-mode bidirectional 
  
  
  VBoxManage guestproperty set $MV_CLIENTE1 /DSBOX/num_interfaces 2
  VBoxManage guestproperty set $MV_CLIENTE1 /DSBOX/eth/0/type static
  VBoxManage guestproperty set $MV_CLIENTE1 /DSBOX/eth/0/address 192.168.100.22
  VBoxManage guestproperty set $MV_CLIENTE1 /DSBOX/eth/0/netmask 24
  VBoxManage guestproperty set $MV_CLIENTE1 /DSBOX/eth/1/type static
  VBoxManage guestproperty set $MV_CLIENTE1 /DSBOX/eth/1/address 10.0.3.15
  VBoxManage guestproperty set $MV_CLIENTE1 /DSBOX/eth/1/netmask 24
  VBoxManage guestproperty set $MV_CLIENTE1 /DSBOX/default_gateway 10.0.3.2
  VBoxManage guestproperty set $MV_CLIENTE1 /DSBOX/default_nameserver 8.8.8.8
  VBoxManage guestproperty set $MV_CLIENTE1 /DSBOX/host_name cliente1.cda.net
  VBoxManage guestproperty set $MV_CLIENTE1 /DSBOX/etc_hosts_dump "ASTERISK.cda.net:192.168.100.11,cliente1.cda.net:192.168.100.22,cliente2.cda.net:192.168.100.33"


  # --- Configuración del Cliente Linphone (VOIP) ---
  # La extensión será ext101
  VBoxManage guestproperty set $MV_CLIENTE1 /DSBOX/voip/client/enabled yes
  VBoxManage guestproperty set $MV_CLIENTE1 /DSBOX/voip/client/user ext101
  VBoxManage guestproperty set $MV_CLIENTE1 /DSBOX/voip/client/realm asterisk
  VBoxManage guestproperty set $MV_CLIENTE1 /DSBOX/voip/client/domain 192.168.100.11
  VBoxManage guestproperty set $MV_CLIENTE1 /DSBOX/voip/client/sip_port 5060
  # ---------------------------------------------------

fi

MV_CLIENTE2="CLIENTE2_$ID"
if ! VBoxManage list vms | grep -q "$MV_CLIENTE2"; then
  # Solo 1 vez
  VBoxManage createvm  --name $MV_CLIENTE2 --basefolder "$DIR_BASE" --register --ostype Debian_64  

  VBoxManage storagectl $MV_CLIENTE2 --name ${MV_CLIENTE2}_storage  --add sata  --portcount 4  2>/dev/null || true
  VBoxManage storagectl $MV_CLIENTE2 --name IDE --add ide 2>/dev/null || true
  VBoxManage storageattach $MV_CLIENTE2 --storagectl ${MV_CLIENTE2}_storage --port 0 --device 0 --type hdd --medium "$IMAGEN_BASE" --mtype multiattach 
  VBoxManage storageattach $MV_CLIENTE2 --storagectl ${MV_CLIENTE2}_storage --port 1 --device 0 --type hdd --medium "$IMAGEN_SWAP" --mtype immutable
  VBoxManage storageattach $MV_CLIENTE2 --storagectl IDE --port 1 --device 0 --type dvddrive --medium none 2>/dev/null || true

  VBoxManage modifyvm $MV_CLIENTE2 --cpus 2 --memory 512 --pae on --vram 16 --graphicscontroller vmsvga
  VBoxManage modifyvm $MV_CLIENTE2 --nic1 intnet --intnet1 vlan1 --macaddress1 080027333333 --cableconnected1 on --nictype1 82540EM
  VBoxManage modifyvm $MV_CLIENTE2 --nic2 nat --macaddress2 080027333303 --cableconnected2 on --nictype2 82540EM

  VBoxManage modifyvm $MV_CLIENTE2 --nat-pf2 "guestssh,tcp,,2224,,22"
  VBoxManage modifyvm $MV_CLIENTE2 --clipboard-mode bidirectional 
  
  
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/num_interfaces 2
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/eth/0/type static
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/eth/0/address 192.168.100.33
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/eth/0/netmask 24
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/eth/1/type static
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/eth/1/address 10.0.3.15
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/eth/1/netmask 24
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/default_gateway 10.0.3.2
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/default_nameserver 8.8.8.8
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/host_name cliente2.cda.net
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/etc_hosts_dump "ASTERISK.cda.net:192.168.100.11,cliente1.cda.net:192.168.100.22,cliente2.cda.net:192.168.100.33"


  # --- Configuración del Cliente Linphone (VOIP) ---
  # La extensión será ext102
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/voip/client/enabled yes
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/voip/client/user ext102
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/voip/client/realm asterisk
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/voip/client/domain 192.168.100.11
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/voip/client/sip_port 5060
  # ---------------------------------------------------

fi

# === GARANTIZAR CONFIGURACIÓN IDE Y ADJUNTAR ISO DE GUEST ADDITIONS ===

adjuntar_ga_ide() {
    local VM=$1
    local ISO=$2
    local IDE_NAME="IDE" # Nombre unificado

    # 1. Intentar CREAR el controlador IDE (Solo si no existe). Suprimir error si ya existe.
    VBoxManage storagectl "$VM" --name "$IDE_NAME" --add ide 2>/dev/null || true

    # 2. Quitar cualquier medio existente (asegura que el puerto esté libre)
    VBoxManage storageattach "$VM" --storagectl "$IDE_NAME" --port 1 --device 0 --type dvddrive --medium none 2>/dev/null || true

    # 3. Adjuntar la ISO de Guest Additions
    if VBoxManage storageattach "$VM" --storagectl "$IDE_NAME" --port 1 --device 0 --type dvddrive --medium "$ISO"; then
         echo ">>> ISO de Guest Additions ($ISO) adjuntada correctamente a $VM."
    else
         echo "Error crítico: Falló al adjuntar la ISO a $VM. Verifique la ruta $ISO."
         exit 1
    fi
}

# === GARANTIZAR CONFIGURACIÓN IDE Y ADJUNTAR ISO DE GUEST ADDITIONS ===

# Usar la función corregida con el nombre "IDE" consistente
adjuntar_ga_ide "$MV_ASTERISK" "$GUEST_ADDITIONS_ISO"
adjuntar_ga_ide "$MV_CLIENTE1" "$GUEST_ADDITIONS_ISO"
adjuntar_ga_ide "$MV_CLIENTE2" "$GUEST_ADDITIONS_ISO"
# ========================================================================

# Cada vez que se quiera arrancar (o directamente desde el interfaz grafico)
VBoxManage startvm $MV_ASTERISK
VBoxManage startvm $MV_CLIENTE1
VBoxManage startvm $MV_CLIENTE2

echo ">>> Tenga paciencia: las máquinas virtuales están arrancando, esto puede tardar varios minutos ..."

### Instalación automática de Guest Additions en cada VM >>> 

instalar_guest_additions() {
    local VM=$1
    local INSTALLED_VERSION
    
    echo ">>> Preparando instalación de Guest Additions en $VM ..."

    # 1. Asegurar estado y adjuntar ISO al controlador (ahora robusto)
    verificar_estado "$VM"
    adjuntar_ga_ide "$VM" "$GUEST_ADDITIONS_ISO"

    # Obtener la versión instalada. Si falla por timeout, la variable queda vacía.
    INSTALLED_VERSION=$(VBoxManage guestproperty get "$VM" "/VirtualBox/GuestAdd/Version" 2>/dev/null | awk '/Value:/ {print $2}')

    # CORRECCIÓN CRÍTICA: Instalar SÓLO si la versión NO COINCIDE o está VACÍA.
    if [ "$INSTALLED_VERSION" != "$VBOX_ISO_VERSION" ]; then
        echo ">>> Instalando/Actualizando Guest Additions (Actual: $INSTALLED_VERSION, Requerida: $VBOX_ISO_VERSION) en $VM..."
        
        # --- BLOQUE DE INSTALACIÓN ROBUSTA ---
        VBoxManage guestcontrol "$VM" run --username root --password purple -- /usr/bin/apt update || echo "guestcontrol falló (apt update)"

        # 1. Instalar dependencias esenciales
        VBoxManage guestcontrol "$VM" run --username root --password purple -- /bin/sh -lc "apt update"
        # Utilizamos 'linux-headers-amd64' para asegurar compatibilidad con el kernel actual
        VBoxManage guestcontrol "$VM" run --username root --password purple -- /bin/sh -lc 'DEBIAN_FRONTEND=noninteractive apt install -y build-essential dkms linux-headers-amd64 mount' || { echo "Error instalando dependencias en $VM"; return 1; }
        # 3. MONTAJE CORREGIDO (Intenta montar por device, luego por label)
        VBoxManage guestcontrol "$VM" run --username root --password purple -- /bin/sh -lc 'mkdir -p /mnt/vbox && (/bin/mount /dev/cdrom /mnt/vbox || /bin/mount /dev/sr0 /mnt/vbox || /bin/mount -L VBox_GAs /mnt/vbox)' || echo "guestcontrol falló (mount cdrom)"
        
        # 4. EJECUTAR INSTALADOR 
        if VBoxManage guestcontrol "$VM" run --username root --password purple -- /bin/sh /mnt/vbox/VBoxLinuxAdditions.run ; then
             echo ">>> Instalador de Guest Additions ejecutado con éxito."
             
             # CORRECCIÓN DE SINCRONIZACIÓN: sleep 10
             echo ">>> Esperando 10 segundos para que el servicio VBoxService inicie antes de reiniciar..."
             sleep 10
             
             # Reiniciar la MV para activar GAs
             VBoxManage controlvm "$VM" reset || true
             echo ">>> Guest Additions instaladas/actualizadas en $VM. Reiniciando."
        else
             echo "guestcontrol falló (run installer). Error de comunicación persistente."
        fi
        
        # Desmontar y limpiar
        VBoxManage guestcontrol "$VM" run --username root --password purple -- /bin/sh -lc 'umount /mnt/vbox' 2>/dev/null || true
    else
        echo ">>> Guest Additions versión $INSTALLED_VERSION ya instalada y lista en $VM."
    fi
}
# Wrapper seguro para ejecutar comandos dentro del invitado sólo si Guest Additions están disponibles
run_guest() {
    local VM="$1"; shift
    if VBoxManage guestproperty get "$VM" "/VirtualBox/GuestAdd/Version" 2>/dev/null | grep -q "Value:" ; then
        VBoxManage guestcontrol "$VM" run --username root --password purple -- "$@"
        return $?
    else
        echo "[run_guest] Guest Additions no disponibles en $VM — se omite el comando: $*"
        return 2
    fi
}

# Llamar a la función para cada VM
sleep 60
instalar_guest_additions "$MV_ASTERISK"
instalar_guest_additions "$MV_CLIENTE1"
instalar_guest_additions "$MV_CLIENTE2"

wait_for_guest_ready() {
    local VM=$1
    echo ">>> Esperando a que $VM se reinicie y Guest Additions esté lista..."
    # 1. Asegura que la VM está corriendo (la habías apagado con reset)
    VBoxManage startvm "$VM" --type headless 2>/dev/null || true 
    # 2. Espera a que el Guest Additions Agent envíe una propiedad (e.g., el Release del SO)
    #    Esto confirma que el SO ha terminado de arrancar y el agente está activo.
    VBoxManage guestproperty wait "$VM" /VirtualBox/GuestAdd/OS/Release --timeout 60000 
    echo ">>> $VM está lista para la configuración final."
}

wait_for_guest_ready "$MV_ASTERISK"
wait_for_guest_ready "$MV_CLIENTE1"
wait_for_guest_ready "$MV_CLIENTE2"

echo ">>> Esperando 10 segundos extra para la inicialización del servicio de ejecución..."
sleep 10

# ============================================================
# INSTALAR ASTERISK EN LA MV ASTERISK
# ============================================================
echo ">>> Instalando Asterisk en $MV_ASTERISK ..."

VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- /usr/bin/apt update
VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- /usr/bin/apt install -y asterisk

VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- /usr/bin/apt install -y asterisk-prompt-es asterisk-prompt-es-extra
VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- /usr/bin/apt install -y asterisk-core-sounds-es asterisk-extra-sounds-es

# --- Volcado de CDR.CONF (Base64) ---
CDR_BASE64=$(echo "$CDR_CONF_CONTENT" | base64 -w 0)
VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- /bin/bash -c "echo \"$CDR_BASE64\" | base64 -d | tee /etc/asterisk/cdr.conf"

# --- Volcado de CEL.CONF (Base64) ---
CEL_BASE64=$(echo "$CEL_CONF_CONTENT" | base64 -w 0)
VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- /bin/bash -c "echo \"$CEL_BASE64\" | base64 -d | tee /etc/asterisk/cel.conf"

# --- Volcado de SIP.CONF (Base64) ---
SIP_BASE64=$(echo "$SIP_CONF_CONTENT" | base64 -w 0)
VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- /bin/bash -c "echo \"$SIP_BASE64\" | base64 -d | tee /etc/asterisk/sip.conf"

# --- Volcado de EXTENSIONS.CONF (Base64) ---
EXTENSIONS_BASE64=$(echo "$EXTENSIONS_CONF_CONTENT" | base64 -w 0)
VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- /bin/bash -c "echo \"$EXTENSIONS_BASE64\" | base64 -d | tee /etc/asterisk/extensions.conf"

# --- Volcado de VOICEMAIL.CONF (Base64) ---
VOICEMAIL_BASE64=$(echo "$VOICEMAIL_CONF_CONTENT" | base64 -w 0)
VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- /bin/bash -c "echo \"$VOICEMAIL_BASE64\" | base64 -d | tee /etc/asterisk/voicemail.conf"

VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- /bin/bash -c "/usr/sbin/asterisk -rx 'sip reload'"
VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- /bin/bash -c "/usr/sbin/asterisk -rx 'dialplan reload'"
VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- /bin/bash -c "/usr/sbin/asterisk -rx 'voicemail reload'"


VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- /usr/bin/systemctl restart asterisk

VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- /bin/bash -c "chown -R asterisk:asterisk /var/lib/asterisk/sounds"

echo ">>> Asterisk instalado y configurado correctamente."

# --- NUEVA LÍNEA CRÍTICA DE ESPERA ---
echo ">>> Esperando 15 segundos para asegurar que Asterisk ha arrancado por completo y cargado SIP..."
sleep 15 
# --------------------------------------


## Función para instalar Linphone de forma robusta en un invitado
install_linphone_on() {
    local VM="$1"; local SIP_USER="$2"; local SIP_PASS="$3"; local GUEST_USER="$4"

    echo ">>> Instalando Linphone en $VM (usuario SIP: $SIP_USER) ..."

    # Verificar que Guest Additions están disponibles
    if ! VBoxManage guestproperty get "$VM" "/VirtualBox/GuestAdd/Version" 2>/dev/null | grep -q "Value:" ; then
        echo ">>> Guest Additions no detectadas en $VM — omitiendo instalación automática."
        return 1
    fi

    # Detectar gestor de paquetes dentro del invitado (se ejecuta en el guest)
    PKG_MGR=$(VBoxManage guestcontrol "$VM" run --username root --password purple -- /bin/sh -lc 'if command -v apt >/dev/null 2>&1; then echo apt; elif command -v apk >/dev/null 2>&1; then echo apk; elif command -v dnf >/dev/null 2>&1; then echo dnf; elif command -v yum >/dev/null 2>&1; then echo yum; elif command -v pacman >/dev/null 2>&1; then echo pacman; else echo none; fi' 2>/dev/null | tr -d '\r' || echo none)

    echo ">>> Gestor de paquetes detectado en $VM: $PKG_MGR"

    case "$PKG_MGR" in
        apt)
            VBoxManage guestcontrol "$VM" run --username root --password purple -- /bin/sh -lc 'export DEBIAN_FRONTEND=noninteractive; apt update && apt install -y linphone linphone-nogtk linphone-cli || true'
            ;;
        apk)
            VBoxManage guestcontrol "$VM" run --username root --password purple -- /bin/sh -lc 'apk update && apk add linphone || true'
            ;;
        dnf)
            VBoxManage guestcontrol "$VM" run --username root --password purple -- /bin/sh -lc 'dnf -y install linphone || true'
            ;;
        yum)
            VBoxManage guestcontrol "$VM" run --username root --password purple -- /bin/sh -lc 'yum -y install linphone || true'
            ;;
        pacman)
            VBoxManage guestcontrol "$VM" run --username root --password purple -- /bin/sh -lc 'pacman -Syu --noconfirm linphone || true'
            ;;
        *)
            echo ">>> No se ha encontrado un gestor de paquetes soportado en $VM. Instalación manual necesaria."
            return 2
            ;;
    esac

    # Crear archivo de configuración .linphonerc como root y ajustar propietario
    VBoxManage guestcontrol "$VM" run --username root --password purple -- /bin/sh -lc 'mkdir -p /home/$GUEST_USER || true; cat > /home/$GUEST_USER/.linphonerc << EOFLINPHONE
    [sip]

    [proxy_0]
    reg_identity=sip:$SIP_USER@192.168.100.11
    reg_proxy=sip:192.168.100.11
    reg_register=1
    auth_userid=$SIP_USER
    auth_passwd=$SIP_PASS
    reg_realm=asterisk

    [video]
    video_enabled=0
    EOFLINPHONE' || echo ">>> Error escribiendo .linphonerc en $VM"

    # 2. NUEVO: Crear directorios necesarios para la DB de Linphone
    VBoxManage guestcontrol "$VM" run --username root --password purple -- /bin/sh -lc "mkdir -p /home/$GUEST_USER/.local/share/linphone"

   # 3. Ajustar propietario RECURSIVAMENTE para incluir .local (MODIFICADO)
    VBoxManage guestcontrol "$VM" run --username root --password purple -- /bin/sh -lc "/usr/bin/chown -R $GUEST_USER:$GUEST_USER /home/$GUEST_USER/.linphonerc /home/$GUEST_USER/.local || true"

    # --- FORZAR REGISTRO EXITOSO ---
    # Usamos la IP de Asterisk: 192.168.100.11 (definida en el script)
    local ASTERISK_IP="192.168.100.11" 

    echo ">>> Forzando registro SIP inicial para $SIP_USER en $VM..."
    # Ejecuta el comando 'register <identity> <proxy> <password>' como el usuario invitado
    VBoxManage guestcontrol "$VM" run --username "$GUEST_USER" --password purple -- /bin/sh -lc "echo -e 'register sip:$SIP_USER@$ASTERISK_IP sip:$ASTERISK_IP $SIP_PASS\nquit' | linphonec" || echo ">>> Falló la ejecución del comando de registro forzado de Linphone en $VM."

    echo ">>> Linphone configurado en $VM"
}

#Llamadas para instalar en CLIENTE1
install_linphone_on "$MV_CLIENTE1" "ext101" "cda1" "usuario"


# INSTALAR LINPHONE EN CLIENTE 2 (usar función centralizada)
install_linphone_on "$MV_CLIENTE2" "ext102" "cda2" "usuario"


