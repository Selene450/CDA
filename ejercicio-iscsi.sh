#!/bin/bash

# Descripcion
TITULO="Ejemplo SAN sobre iSCSI"
CURSO="Centros de Datos, 2025/26"
DIR_BASE_POR_DEFECTO=$HOME/CDA2526

URL_BASE=http://cda.drordas.info
DIR_BASE=${DIR_BASE:-$DIR_BASE_POR_DEFECTO}
DIR_VARLIB=/var/lib/CDA2526


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
    VBoxManage -q storageattach CDA_NO_BORRAR --storagectl CDA_NO_BORRAR_storage --port 0 --device 0 --type hdd --medium none
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




MV_DISCOS="DISCOS_$ID"
if [ ! -e "$DIR_BASE/$MV_DISCOS" ]; then

  # Solo 1 vez
  VBoxManage createvm  --name $MV_DISCOS --basefolder "$DIR_BASE" --register  --ostype Debian_64  
  VBoxManage storagectl $MV_DISCOS --name ${MV_DISCOS}_storage  --add sata --portcount 8
  VBoxManage storageattach $MV_DISCOS --storagectl ${MV_DISCOS}_storage --port 0 --device 0 --type hdd --medium "$IMAGEN_BASE" --mtype multiattach 
  VBoxManage storageattach $MV_DISCOS --storagectl ${MV_DISCOS}_storage --port 1 --device 0 --type hdd --medium "$IMAGEN_SWAP" --mtype immutable 

  VBoxManage modifyvm $MV_DISCOS --cpus 2 --memory 512 --pae on --vram 16 --graphicscontroller vmsvga
  VBoxManage modifyvm $MV_DISCOS --nic1 intnet --intnet1 vlan1 --macaddress1 080027111111 --cableconnected1 on --nictype1 82540EM
  VBoxManage modifyvm $MV_DISCOS --nic2 nat --macaddress2 080027111101 --cableconnected2 on --nictype2 82540EM

  VBoxManage modifyvm $MV_DISCOS --nat-pf2 "guestssh,tcp,,2222,,22"
  VBoxManage modifyvm $MV_DISCOS --clipboard-mode bidirectional 
  
  VBoxManage guestproperty set $MV_DISCOS /DSBOX/num_interfaces 2
  VBoxManage guestproperty set $MV_DISCOS /DSBOX/eth/0/type static
  VBoxManage guestproperty set $MV_DISCOS /DSBOX/eth/0/address 192.168.100.11
  VBoxManage guestproperty set $MV_DISCOS /DSBOX/eth/0/netmask 24
  VBoxManage guestproperty set $MV_DISCOS /DSBOX/eth/1/type static
  VBoxManage guestproperty set $MV_DISCOS /DSBOX/eth/1/address 10.0.3.15
  VBoxManage guestproperty set $MV_DISCOS /DSBOX/eth/1/netmask 24
  VBoxManage guestproperty set $MV_DISCOS /DSBOX/default_gateway 10.0.3.2
  VBoxManage guestproperty set $MV_DISCOS /DSBOX/default_nameserver 8.8.8.8
  VBoxManage guestproperty set $MV_DISCOS /DSBOX/host_name discos.cda.net
  VBoxManage guestproperty set $MV_DISCOS /DSBOX/etc_hosts_dump "discos.cda.net:192.168.100.11,cliente1.cda.net:192.168.100.22,cliente2.cda.net:192.168.100.33"

  if [ ! -e "$DIR_BASE/ISCSI1_$MV_DISCOS.vdi" ]; then
    VBoxManage createhd --filename "$DIR_BASE/ISCSI1_$MV_DISCOS.vdi" --size 100 --format VDI
    VBoxManage storageattach $MV_DISCOS --storagectl ${MV_DISCOS}_storage --port 2 --device 0 --type hdd --medium "$DIR_BASE/ISCSI1_$MV_DISCOS.vdi"
  fi
  if [ ! -e "$DIR_BASE/ISCSI2_$MV_DISCOS.vdi" ]; then
    VBoxManage createhd --filename "$DIR_BASE/ISCSI2_$MV_DISCOS.vdi" --size 100 --format VDI
    VBoxManage storageattach $MV_DISCOS --storagectl ${MV_DISCOS}_storage --port 3 --device 0 --type hdd --medium "$DIR_BASE/ISCSI2_$MV_DISCOS.vdi"
  fi
  if [ ! -e "$DIR_BASE/ISCSI3_$MV_DISCOS.vdi" ]; then
    VBoxManage createhd --filename "$DIR_BASE/ISCSI3_$MV_DISCOS.vdi" --size 100 --format VDI
    VBoxManage storageattach $MV_DISCOS --storagectl ${MV_DISCOS}_storage --port 4 --device 0 --type hdd --medium "$DIR_BASE/ISCSI3_$MV_DISCOS.vdi"
  fi
  if [ ! -e "$DIR_BASE/ISCSI4_$MV_DISCOS.vdi" ]; then
    VBoxManage createhd --filename "$DIR_BASE/ISCSI4_$MV_DISCOS.vdi" --size 100 --format VDI
    VBoxManage storageattach $MV_DISCOS --storagectl ${MV_DISCOS}_storage --port 5 --device 0 --type hdd --medium "$DIR_BASE/ISCSI4_$MV_DISCOS.vdi"
  fi
  
fi


MV_CLIENTE1="CLIENTE1_$ID"
if [ ! -e "$DIR_BASE/$MV_CLIENTE1" ]; then
  # Solo 1 vez
  VBoxManage createvm  --name $MV_CLIENTE1 --basefolder "$DIR_BASE" --register --ostype Debian_64   
  VBoxManage storagectl $MV_CLIENTE1 --name ${MV_CLIENTE1}_storage  --add sata --portcount 4     
  VBoxManage storageattach $MV_CLIENTE1 --storagectl ${MV_CLIENTE1}_storage --port 0 --device 0 --type hdd --medium "$IMAGEN_BASE" --mtype multiattach 
  VBoxManage storageattach $MV_CLIENTE1 --storagectl ${MV_CLIENTE1}_storage --port 1 --device 0 --type hdd --medium "$IMAGEN_SWAP" --mtype immutable 
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
  VBoxManage guestproperty set $MV_CLIENTE1 /DSBOX/etc_hosts_dump "discos.cda.net:192.168.100.11,cliente1.cda.net:192.168.100.22,cliente2.cda.net:192.168.100.33"
fi



MV_CLIENTE2="CLIENTE2_$ID"
if [ ! -e "$DIR_BASE/$MV_CLIENTE2" ]; then
  # Solo 1 vez
  VBoxManage createvm  --name $MV_CLIENTE2 --basefolder "$DIR_BASE" --register --ostype Debian_64   
  VBoxManage storagectl $MV_CLIENTE2 --name ${MV_CLIENTE2}_storage  --add sata  --portcount 4   
  VBoxManage storageattach $MV_CLIENTE2 --storagectl ${MV_CLIENTE2}_storage --port 0 --device 0 --type hdd --medium "$IMAGEN_BASE" --mtype multiattach 
  VBoxManage storageattach $MV_CLIENTE2 --storagectl ${MV_CLIENTE2}_storage --port 1 --device 0 --type hdd --medium "$IMAGEN_SWAP" --mtype immutable 
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
  VBoxManage guestproperty set $MV_CLIENTE2 /DSBOX/etc_hosts_dump "discos.cda.net:192.168.100.11,cliente1.cda.net:192.168.100.22,cliente2.cda.net:192.168.100.33"
fi

# Cada vez que se quiera arrancar (o directamente desde el interfaz grafico)
VBoxManage startvm $MV_DISCOS
VBoxManage startvm $MV_CLIENTE1
VBoxManage startvm $MV_CLIENTE2

#VBoxManage controlvm $MV_DISCOS clipboard-mode bidirectional
#VBoxManage controlvm $MV_CLIENTE1 clipboard-mode bidirectional
#VBoxManage controlvm $MV_CLIENTE2 clipboard-mode bidirectional
