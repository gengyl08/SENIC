/*******************************************************************************
 *
 *  NetFPGA-10G http://www.netfpga.org
 *
 *  File:
 *        nf10priv.c
 *
 *  Project:
 *        nic
 *
 *  Author:
 *        Mario Flajslik
 *
 *  Description:
 *        These functions control the card tx/rx operation. 
 *        nf10priv_xmit -- gets called for every transmitted packet
 *                         (on any nf interface)
 *        work_handler  -- gets called when the interrupt handler puts work
 *                         on the queue
 *        nf10priv_send_rx_dsc -- allocates and sends a receive descriptor
 *                                to the nic
 *
 *        There also exists a LOOPBACK_MODE (enabled by defining constant
 *        LOOPBACK_MODE) that allows the driver to be tested on a single
 *        machine. This mode, at receive, flips the last bit in the second
 *        to last octet of the source and destination IP addresses. (e.g.
 *        address 192.168.2.1 is converted to 192.168.3.1 and vice versa).
 *
 *        An example configuration that has been tested with loopback between 
 *        interfaces 0 and 3 (must add static ARP entries, because ARPs
 *        aren't fixed by the LOOPBACK_MODE):
 *            ifconfig nf0 192.168.2.11;
 *            ifconfig nf3 192.168.3.12;
 *            arp -s 192.168.2.12 00:4E:46:31:30:03;
 *            arp -s 192.168.3.11 00:4E:46:31:30:00;
 *
 *            "ping 192.168.2.12" -- should now work with packets going over
 *                                   the wire.
 *
 *
 *  Copyright notice:
 *        Copyright (C) 2010, 2011 The Board of Trustees of The Leland Stanford
 *                                 Junior University
 *
 *  Licence:
 *        This file is part of the NetFPGA 10G development base package.
 *
 *        This file is free code: you can redistribute it and/or modify it under
 *        the terms of the GNU Lesser General Public License version 2.1 as
 *        published by the Free Software Foundation.
 *
 *        This package is distributed in the hope that it will be useful, but
 *        WITHOUT ANY WARRANTY; without even the implied warranty of
 *        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *        Lesser General Public License for more details.
 *
 *        You should have received a copy of the GNU Lesser General Public
 *        License along with the NetFPGA source package.  If not, see
 *        http://www.gnu.org/licenses/.
 *
 */

#include "nf10priv.h"
#include "nicpic.h"
#include <linux/spinlock.h>
#include <linux/pci.h>

#include <linux/netdevice.h>
#include <linux/etherdevice.h>
#include <linux/if_ether.h>
#include <net/ip.h>
#include <net/tcp.h>
#include <linux/time.h>

#define SK_BUFF_ALLOC_SIZE  1533

//#define LOOPBACK_MODE

static DEFINE_SPINLOCK(tx_lock);
static DEFINE_SPINLOCK(work_lock);
static DEFINE_SPINLOCK(rx_dsc_lock);

DECLARE_WORK(wq, work_handler);

extern char *msg;
static int enqueue = 0;
static int feedback = 0;

int nf10priv_xmit(struct nf10_card *card, struct sk_buff *skb, int port){
    uint8_t* data = skb->data;
    uint32_t len = skb->len;
    unsigned long flags;
    uint64_t dsc_index = 0;
    uint64_t port_decoded = 0;
    uint64_t dsc_l0, dsc_l1;
    uint64_t dma_addr;
    uint64_t class_index = skb->mark;
    uint64_t port_short;
    struct timeval t;

    //decide which class does this packet belong to
    if(*(uint16_t *)(skb->data) <= 500)
        class_index = *(uint16_t*)(skb->data) - 1;
    else
        class_index = 0;
    //if(*(char*)(skb->data+16) == 'Y')
    //    class_index = 1;
    //printk(KERN_EMERG "xmit\n");
    //printk(KERN_EMERG "class_index: %d", class_index);
    if(card->debug){
        printk(KERN_EMERG "class_index: %d", class_index);
        printk(KERN_EMERG "dsc buff head: %d, dsc buff tail: %d", atomic64_read(&card->dsc_buffs[class_index]->head), card->dsc_buffs[class_index]->tail);
    }
    if(len > 1514)
        printk(KERN_ERR "nf10: ERROR too big packet. TX size: %d\n", len);

    // packet buffer management
    spin_lock_irqsave(&tx_lock, flags);

    if(!(atomic64_read(&card->dsc_buffs[class_index]->head) == 0 && card->dsc_buffs[class_index]->tail == ((card->dsc_buffs[class_index]->mask)>>6))
       && !(atomic64_read(&card->dsc_buffs[class_index]->head) != 0 && card->dsc_buffs[class_index]->tail == atomic64_read(&card->dsc_buffs[class_index]->head) - 1)){
        //if(*(char*)(skb->data+16) == 'Y' && enqueue < 256){
        //    do_gettimeofday(&t);
        //    //printk(KERN_EMERG "enqueue: %d, %d\n", sizeof(t.tv_sec), sizeof(t.tv_usec));
        //    memcpy(msg+32*enqueue, &t.tv_sec, 8);
        //    memcpy(msg+32*enqueue+8, &t.tv_usec, 8);
        //    enqueue++;
       // }
        if(class_index == 0 && net_ratelimit())
        printk(KERN_EMERG "dsc buff head: %d, dsc buff tail: %d", atomic64_read(&card->dsc_buffs[class_index]->head), card->dsc_buffs[class_index]->tail);

        dsc_index = card->dsc_buffs[class_index]->tail;
        card->dsc_buffs[class_index]->tail = ((card->dsc_buffs[class_index]->tail+1) & ((card->dsc_buffs[class_index]->mask)>>6));
        dma_addr = pci_map_single(card->pdev, data, len, PCI_DMA_TODEVICE);
        
        if(pci_dma_mapping_error(card->pdev, dma_addr)){
            printk(KERN_ERR "nf10: dma mapping error");
            spin_unlock_irqrestore(&tx_lock, flags);
            return -1;
        }

    } 
    else{
        spin_unlock_irqrestore(&tx_lock, flags);
        return -1;
    }
    
    
    // figure out ports
    if(port == 0){
        port_decoded = 0x0102;
        port_short = 0x1ULL;
    }
    else if(port == 1){
        port_decoded = 0x0408;
        port_short = 0x2ULL;
    }
    else if(port == 2){
        port_decoded = 0x1020;
        port_short = 0x4ULL;
    }
    else if(port == 3){
        port_decoded = 0x4080;
        port_short = 0x8ULL;
    }
    else{
        port_short = 0x1ULL;
    }

    // prepare TX descriptor
    dsc_l0 = ((uint64_t)len << 48) + ((uint64_t)port_decoded << 32) + 0xffffffff;
    dsc_l1 = dma_addr;

    // book keeping
    card->dsc_buffs[class_index]->skb[dsc_index] = skb;
    card->dsc_buffs[class_index]->pkt_physical_addr[dsc_index] = dma_addr;

    mb();
    *(((uint64_t*)card->dsc_buffs[class_index]->ptr) + 8 * dsc_index + 0) = dsc_l0;
    *(((uint64_t*)card->dsc_buffs[class_index]->ptr) + 8 * dsc_index + 1) = dsc_l1;
    mb();
    doorbell_add_dsc(card, class_index, dma_addr, port_short,
                     len, card->dsc_buffs[class_index]->tail);
    spin_unlock_irqrestore(&tx_lock, flags);

    return 0;
}

void work_handler(struct work_struct *w){
    struct nf10_card * card = ((struct my_work_t *)w)->card;
    int irq_done = 0;
    uint64_t tx_int;
    uint32_t tx_doorbell_int;
    uint64_t rx_int;
    uint64_t addr;
    uint64_t index;
    struct sk_buff *skb;
    uint64_t len;
    int port = -1;
    uint64_t port_encoded;
    unsigned long flags;
#ifdef LOOPBACK_MODE
    struct iphdr *iph;
    struct tcphdr *th;
    struct sock sck;
    struct inet_sock *isck;
#endif
    int work_counter = 0;
    int tcnt = 1;
    int int_enabled = 1;
    int i;
    uint64_t class_index;
    uint64_t start, end;
    struct timeval t;

    //printk(KERN_INFO "interrupt!\n");
    spin_lock_irqsave(&work_lock, flags);

    while(tcnt){

        if((int_enabled == 1) && work_counter > 0){
            int_enabled = 0;
            mb();
            *(((uint64_t*)card->cfg_addr)+25) = 0; // disable TX interrupts
            *(((uint64_t*)card->cfg_addr)+26) = 0; // disable RX interrupts
            *(((uint64_t*)card->cfg_addr)+39) = 0;
            mb();
        }

        irq_done = 1;
        
        // read the host completion buffers
        tx_int = *(((uint64_t*)card->host_tx_dne_ptr) + (card->host_tx_dne.rd_ptr)/8);
        rx_int = *(((uint64_t*)card->host_rx_dne_ptr) + (card->host_rx_dne.rd_ptr)/8 + 7);
        tx_doorbell_int = *(((uint32_t*)card->host_tx_doorbell_dne_ptr) + (card->host_tx_doorbell_dne.rd_ptr)/4);

        if( (tx_doorbell_int & 0xff) == 1 ){
            irq_done = 0;
            // manage host completion buffer
            addr = card->host_tx_doorbell_dne.rd_ptr;
            card->host_tx_doorbell_dne.rd_ptr = (addr + 64) & card->host_tx_doorbell_dne.mask;
            index = addr / 64;
            
            // invalidate host tx completion buffer
            *(((uint32_t*)card->host_tx_doorbell_dne_ptr) + index * 16) = 0xffffffff;
            *(((uint32_t*)card->host_tx_doorbell_dne_ptr) + index * 16 + 1) = 0xffffffff;
            mb();
            *(((uint64_t*)card->cfg_addr)+41) = card->host_tx_doorbell_dne.rd_ptr;
            mb();
            //printk(KERN_EMERG "doorbell dne interrupt!\n");
            //printk(KERN_EMERG "%x\n", tx_doorbell_int);
            
            atomic64_dec(&card->mem_tx_doorbell.cnt);
            /*
            if(((tx_doorbell_int>>16) & 0x3f) == 6 && ((tx_doorbell_int>>8) & 0x1) == 1)
            {
                card->class_num--;
                for(i=card->dsc_buffs[card->class_num]->head; i<card->dsc_buffs[card->class_num]->tail; i++){
                   pci_unmap_single(card->pdev, card->dsc_buffs[card->class_num]->pkt_physical_addr[i],
                                    card->dsc_buffs[card->class_num]->skb[i]->len, PCI_DMA_TODEVICE);
                   dev_kfree_skb_any(card->dsc_buffs[card->class_num]->skb[i]);
                }
                kfree(card->dsc_buffs[card->class_num]->skb);
                kfree(card->dsc_buffs[card->class_num]->pkt_physical_addr);
                pci_free_consistent(card->pdev, card->dsc_buffs[card->class_num]->mask+65,
                                    card->dsc_buffs[card->class_num]->ptr_ori,
                                    card->dsc_buffs[card->class_num]->physical_addr_ori);
                kfree(card->dsc_buffs[card->class_num]);
            }
            */
        }

        if( (tx_int & 0xffff) == 1 ){
            irq_done = 0;
            
            // manage host completion buffer
            addr = card->host_tx_dne.rd_ptr;
            card->host_tx_dne.rd_ptr = (addr + 64) & card->host_tx_dne.mask;
            index = addr / 64;
            
            /*
            // clean up the skb
            pci_unmap_single(card->pdev, card->tx_bk_dma_addr[index], card->tx_bk_skb[index]->len, PCI_DMA_TODEVICE);
            dev_kfree_skb_any(card->tx_bk_skb[index]);
            atomic64_sub(card->tx_bk_size[index], &card->mem_tx_pkt.cnt);
            atomic64_dec(&card->mem_tx_dsc.cnt);
            */
            // invalidate host tx completion buffer
            *(((uint32_t*)card->host_tx_dne_ptr) + index * 16) = 0xffffffff;
            *(((uint32_t*)card->host_tx_dne_ptr) + index * 16 + 1) = 0xffffffff;
            mb();
            *(((uint64_t*)card->cfg_addr)+40) = card->host_tx_dne.rd_ptr;
            start = *(((uint64_t*)card->cfg_addr)+50);
            end = *(((uint64_t*)card->cfg_addr)+51);
            mb();
            //do_gettimeofday(&t);
            //printk(KERN_EMERG "%d %d", start, end);
            if(enqueue<512)
            {
                memcpy(msg+16*enqueue, &start, 8);
                memcpy(msg+16*enqueue+8, &end, 8);
                enqueue++;
            }
            //printk(KERN_EMERG "tx dne interrupt!\n");
            //printk(KERN_EMERG "%d\n", (int)((tx_int >> 16) & 0xffff));
            //printk(KERN_EMERG "%x\n", (tx_int >> 32));
            class_index = ((tx_int >> 16) & 0xffff);
            i = atomic64_read(&card->dsc_buffs[class_index]->head);
            while(i != (tx_int>>32)){
                pci_unmap_single(card->pdev, card->dsc_buffs[class_index]->pkt_physical_addr[i],
                                 card->dsc_buffs[class_index]->skb[i]->len, PCI_DMA_TODEVICE);
                dev_kfree_skb_any(card->dsc_buffs[class_index]->skb[i]);
                i = ((i+1) & ((card->dsc_buffs[class_index]->mask)>>6));
            }
            atomic64_set(&card->dsc_buffs[((tx_int >> 16) & 0xffff)]->head, (tx_int >> 32));
            /*
            // restart queue if needed
            if( ((atomic64_read(&card->mem_tx_dsc.cnt) + 8*1) <= card->mem_tx_dsc.cl_size) &&
                ((atomic64_read(&card->mem_tx_pkt.cnt) + 4*32) <= card->mem_tx_pkt.cl_size) ){
                
                for(i = 0; i < 4; i++){
                    if(netif_queue_stopped(card->ndev[i]))
                        netif_wake_queue(card->ndev[i]);
                }

            }*/
        }
        
        if( ((rx_int >> 48) & 0xffff) != 0xffff ){
            irq_done = 0;
                
            // manage host completion buffer
            addr = card->host_rx_dne.rd_ptr;
            card->host_rx_dne.rd_ptr = (addr + 64) & card->host_rx_dne.mask;
            index = addr / 64;
            
            // invalidate host rx completion buffer
            *(((uint64_t*)card->host_rx_dne_ptr) + index * 8 + 7) = 0xffffffffffffffffULL;

            // skb is now ready
            skb = card->rx_bk_skb[index];
            pci_unmap_single(card->pdev, card->rx_bk_dma_addr[index], skb->len, PCI_DMA_FROMDEVICE);
            atomic64_sub(card->rx_bk_size[index], &card->mem_rx_pkt.cnt);
            atomic64_dec(&card->mem_rx_dsc.cnt);
            
            // give the card a new RX descriptor
            nf10priv_send_rx_dsc(card);

            // read data from the completion buffer
            len = rx_int & 0xffff;
            port_encoded = (rx_int >> 16) & 0xffff;
            
            if(port_encoded & 0x0200)
                port = 0;
            else if(port_encoded & 0x0800)
                port = 1;
            else if(port_encoded & 0x2000)
                port = 2;
            else if(port_encoded & 0x8000)
                port = 3;
            else 
                port = -1;

            //printk(KERN_INFO "port_encoded: %x\n", port_encoded);
            //printk(KERN_INFO "len: %d\n", len);
            //port = 0;

            //printk(KERN_ERR "rec %d\n", len);
            //if(*((char *)(skb->data+16)) == (char)1 && feedback<256){
            //    do_gettimeofday(&t);
                //printk(KERN_EMERG "feedback: %d %d\n", t.tv_sec, t.tv_usec);
            //    memcpy(msg+32*feedback+16, &t.tv_sec, 8);
            //    memcpy(msg+32*feedback+24, &t.tv_usec, 8);
            //    feedback++;
            //}

            if(len > 1514 || len < 60 || port < 0 || port > 3){
                printk(KERN_ERR"nf10: invalid pakcet\n");
            }
            else if(((struct nf10_ndev_priv*)netdev_priv(card->ndev[port]))->port_up){

                // update skb with port information
                skb_put(skb, len);            
                
                skb->dev = card->ndev[port];
                skb->protocol = eth_type_trans(skb, card->ndev[port]);
                skb->ip_summed = CHECKSUM_NONE;

                // update stats
                card->ndev[port]->stats.rx_packets++;
                card->ndev[port]->stats.rx_bytes += skb->len;

#ifdef LOOPBACK_MODE
                iph = (struct iphdr *)skb->data;
                if(skb->protocol == htons(ETH_P_IP)){
                    ((uint8_t*)skb->data)[14] ^= 0x1;
                    ((uint8_t*)skb->data)[18] ^= 0x1;
                    ip_send_check(iph);
                    if(((uint8_t*)skb->data)[9] == 6){
                        memset(&sck, 0, sizeof(sck));
                        th = tcp_hdr(skb);
                        th->check = 0;
                        skb->ip_summed = CHECKSUM_PARTIAL;
                        isck = inet_sk(&sck);
                        isck->inet_saddr = iph->saddr;
                        isck->inet_daddr = iph->daddr;
                        tcp_v4_send_check(&sck, skb);
                    }

                    if(((uint8_t*)skb->data)[9] == 17){
                        ((uint8_t*)skb->data)[26] = 0;
                        ((uint8_t*)skb->data)[27] = 0;
                    }
               
                    netif_receive_skb(skb);
                    
                }
                else{
                    kfree_skb(skb);
                }
#else
                netif_receive_skb(skb);
#endif            
            }
            else{ // invalid or down port, drop packet
                kfree_skb(skb);
            }
        }

        work_counter++;

        if(irq_done)
            tcnt--;
        else if(tcnt < 10000)
            tcnt++;

        if((tcnt <= 1) && (int_enabled == 0)){
            work_counter = 0;
            tcnt = 1;
            int_enabled = 1;
            mb();
            *(((uint64_t*)card->cfg_addr)+25) = 1; // enable TX interrupts
            *(((uint64_t*)card->cfg_addr)+26) = 1; // enable RX interrupts
            *(((uint64_t*)card->cfg_addr)+39) = 1;
            mb();
        }
    }

    spin_unlock_irqrestore(&work_lock, flags);
}

int nf10priv_send_rx_dsc(struct nf10_card *card){
    struct sk_buff *skb;
    uint64_t dma_addr;
    uint64_t pkt_addr = 0, pkt_addr_fixed = 0;
    uint64_t dsc_addr = 0, dsc_index = 0;
    uint64_t cl_size = (SK_BUFF_ALLOC_SIZE + 66) / 64;
    unsigned long flags;
    uint64_t dsc_l0, dsc_l1;

    // packet buffer management
    spin_lock_irqsave(&rx_dsc_lock, flags);

    // make sure we fit in the descriptor ring and packet buffer
    if( (atomic64_read(&card->mem_rx_dsc.cnt) + 1 <= card->mem_rx_dsc.cl_size) &&
        (atomic64_read(&card->mem_rx_pkt.cnt) + cl_size <= card->mem_rx_pkt.cl_size)){
        
        skb = dev_alloc_skb(SK_BUFF_ALLOC_SIZE + 2);
        if(!skb) {
            printk(KERN_ERR "nf10: skb alloc failed\n");
            spin_unlock_irqrestore(&rx_dsc_lock, flags);
            return -1;
        }
        skb_reserve(skb, 2); /* align IP on 16B boundary */   

        pkt_addr = card->mem_rx_pkt.wr_ptr;
        card->mem_rx_pkt.wr_ptr = (pkt_addr + 64*cl_size) & card->mem_rx_pkt.mask;

        dsc_addr = card->mem_rx_dsc.wr_ptr;
        card->mem_rx_dsc.wr_ptr = (dsc_addr + 64) & card->mem_rx_dsc.mask;

        atomic64_inc(&card->mem_rx_dsc.cnt);
        atomic64_add(cl_size, &card->mem_rx_pkt.cnt);
        
    } 
    else{
        spin_unlock_irqrestore(&rx_dsc_lock, flags);
        return -1;
    }

    spin_unlock_irqrestore(&rx_dsc_lock, flags);

    dsc_index = dsc_addr / 64;

    // physical address
    dma_addr = pci_map_single(card->pdev, skb->data, SK_BUFF_ALLOC_SIZE, PCI_DMA_FROMDEVICE);

    // fix address for alignment issues
    pkt_addr_fixed = pkt_addr + (dma_addr & 0x3ULL);

    // prepare RX descriptor
    dsc_l0 = ((uint64_t)SK_BUFF_ALLOC_SIZE << 48) + (pkt_addr_fixed & 0xffffffff);
    dsc_l1 = dma_addr;

    // book keeping
    card->rx_bk_dma_addr[dsc_index] = dma_addr;
    card->rx_bk_skb[dsc_index] = skb;
    card->rx_bk_size[dsc_index] = cl_size;

    // write to the card
    mb();
    *(((uint64_t*)card->rx_dsc) + 8 * dsc_index + 0) = dsc_l0;
    *(((uint64_t*)card->rx_dsc) + 8 * dsc_index + 1) = dsc_l1;
    mb();

    return 0;
}
