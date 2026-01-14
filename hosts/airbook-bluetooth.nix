{ config, lib, pkgs, ... }:

# Airbook-specific hardware configuration:
# - Bluetooth device pairing (SEENDA keyboard and mouse)
# - Closed-lid boot handling (disable internal display on boot if lid closed)

let
  btAdapterMAC = "30:35:AD:A2:51:67";

  keyboardMAC = "C5:69:86:F3:48:C2";
  keyboardInfo = ''
    [General]
    Name=SEENDA COE200 KB
    Appearance=0x03c1
    AddressType=static
    SupportedTechnologies=LE;
    Trusted=true
    Blocked=false
    CablePairing=false
    WakeAllowed=true
    Services=00001800-0000-1000-8000-00805f9b34fb;00001801-0000-1000-8000-00805f9b34fb;0000180a-0000-1000-8000-00805f9b34fb;0000180f-0000-1000-8000-00805f9b34fb;00001812-0000-1000-8000-00805f9b34fb;0000fff0-0000-1000-8000-00805f9b34fb;

    [IdentityResolvingKey]
    Key=DBC692CEF7A35E34869CF7B4BF3D2ECB

    [LongTermKey]
    Key=0941BDE2BB0A13F60D7E48232CDCFAD7
    Authenticated=0
    EncSize=16
    EDiv=51189
    Rand=2641808354939232188

    [PeripheralLongTermKey]
    Key=EE79B496157D111931F3BB5D297E861D
    Authenticated=0
    EncSize=16
    EDiv=10475
    Rand=13449669660310563565

    [SlaveLongTermKey]
    Key=EE79B496157D111931F3BB5D297E861D
    Authenticated=0
    EncSize=16
    EDiv=10475
    Rand=13449669660310563565

    [LocalSignatureKey]
    Key=D87F668DC5A954F41D1FFEE9DE2F57E7
    Counter=0
    Authenticated=false

    [RemoteSignatureKey]
    Key=F47AB6C67A7516605EB20045C6CAFFA1
    Counter=0
    Authenticated=false

    [DeviceID]
    Source=2
    Vendor=13652
    Product=62981
    Version=256

    [ConnectionParameters]
    MinInterval=24
    MaxInterval=24
    Latency=12
    Timeout=200
  '';

  mouseMAC = "CF:06:56:4B:BA:8E";
  mouseInfo = ''
    [General]
    Name=SEENDA COE200 MS
    Appearance=0x03c2
    AddressType=static
    SupportedTechnologies=LE;
    Trusted=true
    Blocked=false
    CablePairing=false
    WakeAllowed=true
    Services=00001800-0000-1000-8000-00805f9b34fb;0000180a-0000-1000-8000-00805f9b34fb;0000180f-0000-1000-8000-00805f9b34fb;00001812-0000-1000-8000-00805f9b34fb;0000fff0-0000-1000-8000-00805f9b34fb;

    [IdentityResolvingKey]
    Key=79BBD2850DB13D6B09302BD48FF00F91

    [LongTermKey]
    Key=00D53309FBAF854D482FADAADD2FB96A
    Authenticated=0
    EncSize=16
    EDiv=48510
    Rand=2897003849228855201

    [PeripheralLongTermKey]
    Key=F6FD31D2F387B17997BA198C91A8F129
    Authenticated=0
    EncSize=16
    EDiv=50860
    Rand=2832843564590233837

    [SlaveLongTermKey]
    Key=F6FD31D2F387B17997BA198C91A8F129
    Authenticated=0
    EncSize=16
    EDiv=50860
    Rand=2832843564590233837

    [LocalSignatureKey]
    Key=AC2055BC473E7027EB60485E6EFA9F6A
    Counter=0
    Authenticated=false

    [RemoteSignatureKey]
    Key=C1DA5BED6D26D69155C885B29408D0C9
    Counter=0
    Authenticated=false

    [DeviceID]
    Source=2
    Vendor=14
    Product=13330
    Version=1799

    [ConnectionParameters]
    MinInterval=7
    MaxInterval=7
    Latency=48
    Timeout=300
  '';
in
{
  # Deploy bluetooth pairing info on system activation
  system.activationScripts.bluetooth-pairing = lib.stringAfter [ "var" ] ''
    mkdir -p /var/lib/bluetooth/${btAdapterMAC}/${keyboardMAC}
    mkdir -p /var/lib/bluetooth/${btAdapterMAC}/${mouseMAC}

    cat > /var/lib/bluetooth/${btAdapterMAC}/${keyboardMAC}/info << 'EOF'
${keyboardInfo}
EOF

    cat > /var/lib/bluetooth/${btAdapterMAC}/${mouseMAC}/info << 'EOF'
${mouseInfo}
EOF

    chmod 700 /var/lib/bluetooth/${btAdapterMAC}
    chmod 700 /var/lib/bluetooth/${btAdapterMAC}/${keyboardMAC}
    chmod 700 /var/lib/bluetooth/${btAdapterMAC}/${mouseMAC}
    chmod 600 /var/lib/bluetooth/${btAdapterMAC}/${keyboardMAC}/info
    chmod 600 /var/lib/bluetooth/${btAdapterMAC}/${mouseMAC}/info
  '';

  # Disable internal display on login if lid is closed
  # This runs when the display manager starts
  services.displayManager.sessionCommands = ''
    # Check if lid is closed
    LID_STATE=$(cat /proc/acpi/button/lid/LID*/state 2>/dev/null | awk '{print $2}')
    if [ "$LID_STATE" = "closed" ]; then
      # Find and disable internal display (eDP)
      INTERNAL=$(${pkgs.xorg.xrandr}/bin/xrandr | grep -E '^eDP' | awk '{print $1}')
      if [ -n "$INTERNAL" ]; then
        ${pkgs.xorg.xrandr}/bin/xrandr --output "$INTERNAL" --off
      fi
    fi
  '';
}
