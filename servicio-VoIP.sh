#!/bin/bash

# Descripcion
TITULO="Solución VoIP con Asterisk y Linphone"
CURSO="Centros de Datos, 2025/26"
DIR_BASE_POR_DEFECTO=$HOME/CDA2526

URL_BASE=http://cda.drordas.info
DIR_BASE=${DIR_BASE:-$DIR_BASE_POR_DEFECTO}
DIR_VARLIB=/var/lib/CDA2526

HOST_IFACE=$(ip route | awk '/default/ {print $5; exit}')

# =========================================================================
# GUEST ADDITIONS: Descarga y Ubicación
# IMPORTANTE: Escoger una versión de Guest Additions compatible con la versión
# de VirtualBox instalada en el Host.
# =========================================================================
VBOX_ISO_VERSION="7.2.4" # <--- VERSION ESTABLE. AJUSTAR SI ES NECESARIO.
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
#!/bin/bash

#!/bin/bash

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
allowoverlap=no
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
[servidorCDA]
exten => 101,1,Dial(SIP/ext101)
exten => 102,1,Dial(SIP/ext102)
EOF_EXTENSIONS_CONF
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
  VBoxManage guestproperty set $MV_CLIENTE1 /DSBOX/voip/client/ha1 7132af494bc78d5019219702cfd741e4
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
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/voip/client/ha1 2b0aa0dcb38301f707afdb7e4f10bac7
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/voip/client/realm asterisk
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/voip/client/domain 192.168.100.11
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/voip/client/sip_port 5060
  # ---------------------------------------------------

fi

# === GARANTIZAR CONFIGURACIÓN IDE (Se ejecuta siempre antes de arrancar) ===
# MV_ASTERISK IDE Configuration
VBoxManage storagectl $MV_ASTERISK --name IDE --add ide 2>/dev/null || true
VBoxManage storageattach $MV_ASTERISK --storagectl IDE --port 1 --device 0 --type dvddrive --medium none 2>/dev/null || true

# MV_CLIENTE1 IDE Configuration
VBoxManage storagectl $MV_CLIENTE1 --name IDE --add ide 2>/dev/null || true
VBoxManage storageattach $MV_CLIENTE1 --storagectl IDE --port 1 --device 0 --type dvddrive --medium none 2>/dev/null || true

# MV_CLIENTE2 IDE Configuration
VBoxManage storagectl $MV_CLIENTE2 --name IDE --add ide 2>/dev/null || true
VBoxManage storageattach $MV_CLIENTE2 --storagectl IDE --port 1 --device 0 --type dvddrive --medium none 2>/dev/null || true
# ==========================================================================

# Cada vez que se quiera arrancar (o directamente desde el interfaz grafico)
VBoxManage startvm $MV_ASTERISK
VBoxManage startvm $MV_CLIENTE1
VBoxManage startvm $MV_CLIENTE2


### Instalación automática de Guest Additions en cada VM >>> 

instalar_guest_additions() {
    local VM=$1

    echo ">>> Preparando instalación de Guest Additions en $VM ..."

    # ... (código para montar la ISO) ...

    if VBoxManage guestproperty get "$VM" "/VirtualBox/GuestAdd/Version" 2>/dev/null | grep -q "Value:" ; then
        echo ">>> Guest Additions ya disponibles: ejecutando instalador dentro del invitado."
        
        # --- CORRECCIÓN: Rutas absolutas y sin 'sudo' (como root) ---
        VBoxManage guestcontrol "$VM" run --username root --password purple -- /usr/bin/apt update || echo "guestcontrol falló (update)"
        VBoxManage guestcontrol "$VM" run --username root --password purple -- /usr/bin/apt install -y build-essential dkms linux-headers-$(/usr/bin/uname -r) || echo "guestcontrol falló (install deps)"
        VBoxManage guestcontrol "$VM" run --username root --password purple -- /bin/sh /media/cdrom/VBoxLinuxAdditions.run || echo "guestcontrol falló (run installer)"
        # -----------------------------------------------------------

        # Desmontar la ISO
        VBoxManage storageattach "$VM" --storagectl "IDE" --port 1 --device 0 --type dvddrive --medium none 2>/dev/null || true

        # Reiniciar la VM para activar Guest Additions
        VBoxManage controlvm "$VM" reset || true

        echo ">>> Guest Additions instaladas/actualizadas en $VM"
    else
        echo ">>> Guest Additions no están instaladas en $VM. He montado la ISO: $GUEST_ADDITIONS_ISO"
        echo ">>> No puedo ejecutar comandos dentro del invitado porque falta Guest Additions."
        echo ">>> Opciones:\n  - Accede manualmente al invitado y ejecuta: sudo sh /media/cdrom/VBoxLinuxAdditions.run\n  - O configura acceso SSH/automatización y reintenta.\n"
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

# ============================================================
# INSTALAR ASTERISK EN LA MV ASTERISK
# ============================================================
echo ">>> Instalando Asterisk en $MV_ASTERISK ..."

VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- /usr/bin/apt update
VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- /usr/bin/apt install -y asterisk

# Crear archivos de configuración
VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- \
    /bin/bash -c "echo \"$CDR_CONF_CONTENT\" | tee /etc/asterisk/cdr.conf"

VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- \
    /bin/bash -c "echo \"$CEL_CONF_CONTENT\" | tee /etc/asterisk/cel.conf"

VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- \
    /bin/bash -c "echo \"$SIP_CONF_CONTENT\" | tee /etc/asterisk/sip.conf"

VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- \
    /bin/bash -c "echo \"$EXTENSIONS_CONF_CONTENT\" | tee /etc/asterisk/extensions.conf"

VBoxManage guestcontrol $MV_ASTERISK run --username root --password purple -- /usr/bin/systemctl restart asterisk

echo ">>> Asterisk instalado correctamente."


# ============================================================
# INSTALAR LINPHONE EN CLIENTE 1
# ============================================================
echo ">>> Instalando Linphone en $MV_CLIENTE1 ..."

# Usar root para comandos de sistema (sin sudo)
VBoxManage guestcontrol $MV_CLIENTE1 run --username root --password purple -- /usr/bin/apt update
VBoxManage guestcontrol $MV_CLIENTE1 run --username root --password purple -- /usr/bin/apt install -y linphone-nogtk

# Usar el usuario 'usuario' para escribir en su directorio home
VBoxManage guestcontrol $MV_CLIENTE1 run --username usuario --password purple -- \
    /bin/bash -c "cat > /home/usuario/.linphonerc << 'EOF'
[sip]
username=ext101
passwd=cda1
domain=192.168.100.11
proxy=sip:192.168.100.11
EOF"

# Asegurar permisos (ejecutar como root)
VBoxManage guestcontrol $MV_CLIENTE1 run --username root --password purple -- \
    /usr/bin/chown usuario:usuario /home/usuario/.linphonerc

echo ">>> Linphone configurado en CLIENTE1"


# ============================================================
# INSTALAR LINPHONE EN CLIENTE 2
# ============================================================
echo ">>> Instalando Linphone en $MV_CLIENTE2 ..."

# Usar root para comandos de sistema (sin sudo)
VBoxManage guestcontrol $MV_CLIENTE2 run --username root --password purple -- /usr/bin/apt update
VBoxManage guestcontrol $MV_CLIENTE2 run --username root --password purple -- /usr/bin/apt install -y linphone-nogtk

# Usar el usuario 'usuario' para escribir en su directorio home
VBoxManage guestcontrol $MV_CLIENTE2 run --username usuario --password purple -- \
    /bin/bash -c "cat > /home/usuario/.config/linphonerc << 'EOF'
[sip]
username=ext102
passwd=cda2
domain=192.168.100.11
proxy=sip:192.168.100.11
EOF"

# Asegurar permisos (ejecutar como root). ¡Ojo! Había un error de ruta (.config/linphonerc vs .linphonerc)
VBoxManage guestcontrol $MV_CLIENTE2 run --username root --password purple -- \
    /usr/bin/chown usuario:usuario /home/usuario/.config/linphonerc

echo ">>> Linphone configurado en CLIENTE2"


