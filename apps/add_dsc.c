#include <fcntl.h>
#include <sys/ioctl.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#define NF10_IOCTL_CMD_READ_STAT (SIOCDEVPRIVATE+0)
#define NF10_IOCTL_CMD_WRITE_REG (SIOCDEVPRIVATE+1)
#define NF10_IOCTL_CMD_READ_REG (SIOCDEVPRIVATE+2)
#define NF10_IOCTL_CMD_ADD_DSC (SIOCDEVPRIVATE+3)

int main(int argc, char* argv[]){
    int f;
    uint64_t v;

    //----------------------------------------------------
    //-- open nf10 file descriptor for all the fun stuff
    //----------------------------------------------------
    f = open("/dev/nf10", O_RDWR);
    if(f < 0){
        perror("/dev/nf10");
        return 0;
    }
    
    printf("\n");
    ioctl(f, NF10_IOCTL_CMD_ADD_DSC, v);
    printf("\n");

    close(f);
    
    return 0;
}
