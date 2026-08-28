#!/usr/bin/python3
import os
import subprocess
import sys

# Workaround to cut SBE image from elf image.
def parserElf(argv):
    try:
        img     = argv[1]
    except:
        print("Missing argument : arg[0] image(.out)")
        exit(1)

    SBE_OUT = img
    binFileName = SBE_OUT.split(".", 1)[0]
    SBE_BIN = binFileName + ".bin"

    #TODO:Need disussion on what will be the first section in pst basis zip design.
    #As per p10 xip its .header. For pst lets take it as .text.
    #firstSection = b".header"
    firstSection = b".startup"

    cmd = "readelf -S "+SBE_OUT
    cmd1 = "nm "+SBE_OUT+" | grep _IMAGE_SIZE"
    output = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE)

    for line in output.stdout:
        line = line.strip()

        if not line: continue

        if( (line.find(firstSection) != -1) ):
            tokens = line.split();
            startSize = int( tokens[5], 16 )
            print(startSize)
            break;

   # Get the location of sbe end
    output = subprocess.Popen(cmd1, shell=True, stdout=subprocess.PIPE)
    for line in output.stdout:
        line = line.strip()
        tokens = line.split();
        endSize = int( tokens[0], 16 );
        print(endSize)
        break;

    if( (startSize == 0) or (endSize == 0)):
        exit(1)

    # cut the image
    cmd2 = "dd skip=" + str(startSize) + " count=" + str(endSize) + " if="+SBE_OUT+" of="+SBE_BIN+" bs=1"
    rc = os.system(cmd2)
    if ( rc ):
       print("ERROR running %s: %d "%( cmd2, rc ))
       exit(1)

parserElf(sys.argv)
