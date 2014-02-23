/*******************************************************************************
 *
 *  NetFPGA-10G http://www.netfpga.org
 *
 *  File:
 *        nf10driver.h
 *
 *  Project:
 *        nic
 *
 *  Author:
 *        Mario Flajslik
 *
 *  Description:
 *        Top level header file for the nic driver. Contains definitions for
 *        nic datastructures.
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

#ifndef NF10DRIVER_H
#define NF10DRIVER_H

#define PCI_VENDOR_ID_NF10 0x10ee
#define PCI_DEVICE_ID_NF10 0x4244
#define DEVICE_NAME "nf10"
#define CLASS_NUM_MAX 1023

#include <linux/netdevice.h> 
#include <linux/cdev.h>
#include <asm/atomic.h>
#include <linux/workqueue.h>

void work_handler(struct work_struct *w);

struct nf10mem{
    uint64_t wr_ptr;
    uint64_t rd_ptr;
    atomic64_t cnt;
    uint64_t mask;
    uint64_t cl_size;
} __attribute__ ((aligned(64)));

struct dsc_buff{
    void *ptr_ori;
    void *ptr;
    uint64_t physical_addr_ori;
    uint64_t physical_addr;
    uint64_t mask;
    int class_index;
    uint64_t head;
    uint64_t tail;
    struct sk_buff *skb;
    uint64_t pkt_physical_addr;
};

struct my_work_t{
    struct work_struct work;
    struct nf10_card *card;
};

struct nf10_card{
    struct workqueue_struct *wq;
    struct my_work_t work;

    volatile void *cfg_addr;   // kernel virtual address of the card BAR0 space
    volatile void *tx_doorbell;     // kernel virtual address of the card tx descriptor space
    volatile void *rx_dsc;     // kernel virtual address of the card rx descriptor space

    uint64_t tx_dsc_mask;
    uint64_t rx_dsc_mask;
    uint64_t tx_pkt_mask;
    uint64_t rx_pkt_mask;
    uint64_t tx_dne_mask;
    uint64_t rx_dne_mask;
    uint64_t tx_doorbell_mask;
    uint64_t tx_doorbell_dne_mask;

    void *host_tx_dne_ptr;         // virtual address
    uint64_t host_tx_dne_dma;      // physical address

    void *host_rx_dne_ptr;         // virtual address
    uint64_t host_rx_dne_dma;      // physical address

    void *host_tx_doorbell_dne_ptr;         // virtual address
    uint64_t host_tx_doorbell_dne_dma;      // physical address
    
    struct pci_dev *pdev;
    struct cdev cdev; // char device structure (for /dev/nf10)

    struct net_device *ndev[4]; // network devices
    
    // memory buffers
    struct nf10mem mem_tx_dsc;
    struct nf10mem mem_tx_pkt;
    struct nf10mem mem_rx_dsc;
    struct nf10mem mem_rx_pkt;
    struct nf10mem host_tx_dne;
    struct nf10mem host_rx_dne;
    struct nf10mem mem_tx_doorbell;
    struct nf10mem host_tx_doorbell_dne;

    // tx book keeping
    struct sk_buff  **tx_bk_skb;
    uint64_t *tx_bk_dma_addr;
    uint64_t *tx_bk_size;
    uint64_t *tx_bk_port;
    struct sk_buff  **rx_bk_skb;
    uint64_t *rx_bk_dma_addr;
    uint64_t *rx_bk_size;

    

    // tx dsc buffer
    struct dsc_buff *dsc_buffs[CLASS_NUM_MAX];
    int class_num;

    uint64_t tx_dsc_buffer_host_mask;
    void *tx_dsc_buffer_ptr, *tx_dsc_buffer_ptr_tmp;
    uint64_t tx_dsc_buffer_host_addr, tx_dsc_buffer_host_addr_tmp;
};

struct nf10_ndev_priv{
    struct nf10_card *card;
    int port_num;
    int port_up;
};


#endif
