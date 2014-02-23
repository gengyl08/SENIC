/*******************************************************************************
 *
 *  NetFPGA-10G http://www.netfpga.org
 *
 *  File:
 *        nf10driver.c
 *
 *  Project:
 *        nic
 *
 *  Author:
 *        Mario Flajslik
 *
 *  Description:
 *        Top level file for the nic driver. Contains functions that are called
 *        when module is loaded/unloaded to initialize/remove PCIe device and
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

#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/stat.h>
#include <linux/pci.h>
#include <linux/fs.h>
#include <asm/uaccess.h>
#include <linux/time.h>
#include "nf10driver.h"
#include "nf10fops.h"
#include "nf10iface.h"
#include "nicpic.h"

#define SK_BUFF_ALLOC_SIZE  1533

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Mario Flajslik");
MODULE_DESCRIPTION("nf10 nic driver");

static int major; 
char *msg;

static struct pci_device_id pci_id[] = {
    {PCI_DEVICE(PCI_VENDOR_ID_NF10, PCI_DEVICE_ID_NF10)},
    {0}
};
MODULE_DEVICE_TABLE(pci, pci_id);

static int __devinit nf10_probe(struct pci_dev *pdev, const struct pci_device_id *id){
	int err;
    int i;
    int ret = -ENODEV;
    struct nf10_card *card;

    uint64_t port_decoded = 0x4080;
    uint32_t pkt_len = 0x81;
    struct sk_buff *skb;
    uint64_t dma_addr;
    uint64_t dsc_l0, dsc_l1;

	// enable device
	if((err = pci_enable_device(pdev))) {
		printk(KERN_ERR "nf10: Unable to enable the PCI device!\n");
        ret = -ENODEV;
		goto err_out_none;
	}

    // set DMA addressing masks (full 64bit)
    if(dma_set_mask(&pdev->dev, DMA_BIT_MASK(64)) < 0){
        printk(KERN_ERR "nf10: dma_set_mask fail!\n");
        ret = -EFAULT;
        goto err_out_disable_device;

        if(dma_set_coherent_mask(&pdev->dev, DMA_BIT_MASK(64)) < 0){
            printk(KERN_ERR "nf10: dma_set_mask fail!\n");
            ret = -EFAULT;
            goto err_out_disable_device;
        }
    }

    // enable BusMaster (enables generation of pcie requests)
	pci_set_master(pdev);

    // enable MSI
    if(pci_enable_msi(pdev) != 0){
        printk(KERN_ERR "nf10: failed to enable MSI interrupts\n");
        ret = -EFAULT;
		goto err_out_disable_device;
    }
	
    // be nice and tell kernel that we'll use this resource
	printk(KERN_INFO "nf10: Reserving memory region for NF10\n");
	if (!request_mem_region(pci_resource_start(pdev, 0), pci_resource_len(pdev, 0), DEVICE_NAME)) {
		printk(KERN_ERR "nf10: Reserving memory region failed\n");
        ret = -ENOMEM;
        goto err_out_msi;
	}
	if (!request_mem_region(pci_resource_start(pdev, 2), pci_resource_len(pdev, 2), DEVICE_NAME)) {
		printk(KERN_ERR "nf10: Reserving memory region failed\n");
        ret = -ENOMEM;
		goto err_out_release_mem_region1;
	}

    // create private structure
	card = (struct nf10_card*)kmalloc(sizeof(struct nf10_card), GFP_KERNEL);
	if (card == NULL) {
		printk(KERN_ERR "nf10: Private card memory alloc failed\n");
		ret = -ENOMEM;
		goto err_out_release_mem_region2;
	}
	memset(card, 0, sizeof(struct nf10_card));
    card->pdev = pdev;
	
    // map the cfg memory
	printk(KERN_INFO "nf10: mapping cfg memory\n");
    card->cfg_addr = ioremap_nocache(pci_resource_start(pdev, 0), pci_resource_len(pdev, 0));
	if (!card->cfg_addr)
	{
		printk(KERN_ERR "nf10: cannot mem region len:%lx start:%lx\n",
			(long unsigned)pci_resource_len(pdev, 0),
			(long unsigned)pci_resource_start(pdev, 0));
		goto err_out_iounmap;
	}

	printk(KERN_INFO "nf10: mapping mem memory\n");

    card->tx_doorbell = ioremap_nocache(pci_resource_start(pdev, 2) + 0 * 0x00100000ULL, 0x00100000ULL);
    card->rx_dsc = ioremap_nocache(pci_resource_start(pdev, 2) + 1 * 0x00100000ULL, 0x00100000ULL);

	if (!card->tx_doorbell || !card->rx_dsc)
	{
		printk(KERN_ERR "nf10: cannot mem region len:%lx start:%lx\n",
			(long unsigned)pci_resource_len(pdev, 2),
			(long unsigned)pci_resource_start(pdev, 2));
		goto err_out_iounmap;
	}

    // reset
    *(((uint64_t*)card->cfg_addr)+30) = 1;
    msleep(1);
    printk(KERN_INFO "reset: %d\n", *(((uint64_t*)card->cfg_addr)+30));

    // set buffer masks
    card->tx_dsc_mask = 0x000007ffULL;
    card->rx_dsc_mask = 0x000007ffULL;
    card->tx_pkt_mask = 0x00007fffULL;
    card->rx_pkt_mask = 0x00007fffULL;
    card->tx_dne_mask = 0x000007ffULL;
    card->rx_dne_mask = 0x000007ffULL;
    card->tx_doorbell_mask  = 0x000007ffULL;
    card->tx_doorbell_dne_mask = 0x000007ffULL;
    /*
    if(card->tx_dsc_mask > card->tx_dne_mask){
        *(((uint64_t*)card->cfg_addr)+1) = card->tx_dne_mask;
        card->tx_dsc_mask = card->tx_dne_mask;
    }
    else if(card->tx_dne_mask > card->tx_dsc_mask){
        *(((uint64_t*)card->cfg_addr)+7) = card->tx_dsc_mask;
        card->tx_dne_mask = card->tx_dsc_mask;
    }

    if(card->rx_dsc_mask > card->rx_dne_mask){
        *(((uint64_t*)card->cfg_addr)+9) = card->rx_dne_mask;
        card->rx_dsc_mask = card->rx_dne_mask;
    }
    else if(card->rx_dne_mask > card->rx_dsc_mask){
        *(((uint64_t*)card->cfg_addr)+15) = card->rx_dsc_mask;
        card->rx_dne_mask = card->rx_dsc_mask;
    }*/

    // allocate buffers to play with
    card->host_tx_dne_ptr = pci_alloc_consistent(pdev, card->tx_dne_mask+1, &(card->host_tx_dne_dma));
    card->host_rx_dne_ptr = pci_alloc_consistent(pdev, card->rx_dne_mask+1, &(card->host_rx_dne_dma));
    card->host_tx_doorbell_dne_ptr = pci_alloc_consistent(pdev, card->tx_doorbell_dne_mask+1, &(card->host_tx_doorbell_dne_dma));

    if( (card->host_rx_dne_ptr == NULL) ||
        (card->host_tx_dne_ptr == NULL) ||
        (card->host_tx_doorbell_dne_ptr == NULL)){
        
        printk(KERN_ERR "nf10: cannot allocate dma buffer\n");
        goto err_out_free_private2;
    }

    // set host buffer addresses
    *(((uint64_t*)card->cfg_addr)+16) = card->host_tx_dne_dma;
    *(((uint64_t*)card->cfg_addr)+17) = card->tx_dne_mask;
    *(((uint64_t*)card->cfg_addr)+18) = card->host_rx_dne_dma;
    *(((uint64_t*)card->cfg_addr)+19) = card->rx_dne_mask;
    *(((uint64_t*)card->cfg_addr)+37) = card->host_tx_doorbell_dne_dma;
    *(((uint64_t*)card->cfg_addr)+38) = card->tx_doorbell_dne_mask;
    printk(KERN_EMERG "2\n");
    // init mem buffers
    card->mem_tx_dsc.wr_ptr = 0;
    card->mem_tx_dsc.rd_ptr = 0;
    atomic64_set(&card->mem_tx_dsc.cnt, 0);
    card->mem_tx_dsc.mask = card->tx_dsc_mask;
    card->mem_tx_dsc.cl_size = (card->tx_dsc_mask+1)/64;
    card->mem_tx_pkt.wr_ptr = 0;
    card->mem_tx_pkt.rd_ptr = 0;
    atomic64_set(&card->mem_tx_pkt.cnt, 0);
    card->mem_tx_pkt.mask = card->tx_pkt_mask;
    card->mem_tx_pkt.cl_size = (card->tx_pkt_mask+1)/64;
    card->mem_rx_dsc.wr_ptr = 0;
    card->mem_rx_dsc.rd_ptr = 0;
    atomic64_set(&card->mem_rx_dsc.cnt, 0);
    card->mem_rx_dsc.mask = card->rx_dsc_mask;
    card->mem_rx_dsc.cl_size = (card->rx_dsc_mask+1)/64;
    card->mem_rx_pkt.wr_ptr = 0;
    card->mem_rx_pkt.rd_ptr = 0;
    atomic64_set(&card->mem_rx_pkt.cnt, 0);
    card->mem_rx_pkt.mask = card->rx_pkt_mask;
    card->mem_rx_pkt.cl_size = (card->rx_pkt_mask+1)/64;
    card->host_tx_dne.wr_ptr = 0;
    card->host_tx_dne.rd_ptr = 0;
    atomic64_set(&card->host_tx_dne.cnt, 0);
    card->host_tx_dne.mask = card->tx_dne_mask;
    card->host_tx_dne.cl_size = (card->tx_dne_mask+1)/64;
    card->host_rx_dne.wr_ptr = 0;
    card->host_rx_dne.rd_ptr = 0;
    atomic64_set(&card->host_rx_dne.cnt, 0);
    card->host_rx_dne.mask = card->rx_dne_mask;
    card->host_rx_dne.cl_size = (card->rx_dne_mask+1)/64;
    card->mem_tx_doorbell.wr_ptr = 0;
    card->mem_tx_doorbell.rd_ptr = 0;
    atomic64_set(&card->mem_tx_doorbell.cnt, 0);
    card->mem_tx_doorbell.mask = card->tx_doorbell_mask;
    card->mem_tx_doorbell.cl_size = (card->tx_doorbell_mask+1)/64;
    card->host_tx_doorbell_dne.wr_ptr = 0;
    card->host_tx_doorbell_dne.rd_ptr = 0;
    atomic64_set(&card->host_tx_doorbell_dne.cnt, 0);
    card->host_tx_doorbell_dne.mask = card->tx_doorbell_dne_mask;
    card->host_tx_doorbell_dne.cl_size = (card->tx_doorbell_dne_mask+1)/64;
    
    for(i = 0; i < card->host_tx_dne.cl_size; i++)
        *(((uint64_t*)card->host_tx_dne_ptr) + i * 8) = 0xffffffffffffffffULL;

    for(i = 0; i < card->host_rx_dne.cl_size; i++)
        *(((uint64_t*)card->host_rx_dne_ptr) + i * 8 + 7) = 0xffffffffffffffffULL;

    for(i = 0; i < card->host_tx_doorbell_dne.cl_size; i++)
        *(((uint32_t*)card->host_tx_doorbell_dne_ptr) + i * 16) = 0xffffffff;

    printk(KERN_EMERG "3\n");

    // initialize work queue
    if(!(card->wq = create_workqueue("int_hndlr"))){
        printk(KERN_ERR "nf10: workqueue failed\n");
    }
    INIT_WORK((struct work_struct*)&card->work, work_handler);
    card->work.card = card;

    // allocate book keeping structures
    card->tx_bk_skb = (struct sk_buff**)kmalloc(card->mem_tx_dsc.cl_size*sizeof(struct sk_buff*), GFP_KERNEL);
    card->tx_bk_dma_addr = (uint64_t*)kmalloc(card->mem_tx_dsc.cl_size*sizeof(uint64_t), GFP_KERNEL);
    card->tx_bk_size = (uint64_t*)kmalloc(card->mem_tx_dsc.cl_size*sizeof(uint64_t), GFP_KERNEL);
    card->tx_bk_port = (uint64_t*)kmalloc(card->mem_tx_dsc.cl_size*sizeof(uint64_t), GFP_KERNEL);

    card->rx_bk_skb = (struct sk_buff**)kmalloc(card->mem_rx_dsc.cl_size*sizeof(struct sk_buff*), GFP_KERNEL);
    card->rx_bk_dma_addr = (uint64_t*)kmalloc(card->mem_rx_dsc.cl_size*sizeof(uint64_t), GFP_KERNEL);
    card->rx_bk_size = (uint64_t*)kmalloc(card->mem_rx_dsc.cl_size*sizeof(uint64_t), GFP_KERNEL);
    
    if(card->tx_bk_skb == NULL || card->tx_bk_dma_addr == NULL || card->tx_bk_size == NULL || card->tx_bk_port == NULL ||
       card->rx_bk_skb == NULL || card->rx_bk_dma_addr == NULL || card->rx_bk_size == NULL){
        printk(KERN_ERR "nf10: kmalloc failed");
        goto err_out_free_private2;
    }

    // initialize descriptors buffers
    card->class_num = 0;

    // store private data to pdev
	pci_set_drvdata(pdev, card);

    // success
    ret = nf10iface_probe(pdev, card);
    if(ret < 0){
        printk(KERN_ERR "nf10: failed to initialize interfaces\n");
        goto err_out_free_private2;
    }

    ret = nf10fops_probe(pdev, card);
    if(ret < 0){
        printk(KERN_ERR "nf10: failed to initialize dev file\n");
        goto err_out_free_private2;
    }
    else{
        /*
        card->tx_dsc_buffer_host_mask = 0x0fff;
        card->tx_dsc_buffer_ptr_tmp = pci_alloc_consistent(pdev, card->tx_dsc_buffer_host_mask+1, &(card->tx_dsc_buffer_host_addr_tmp));
        card->tx_dsc_buffer_ptr = (void *)(((uint64_t)(card->tx_dsc_buffer_ptr_tmp) & 0xffffffffffffffc0ULL) + 0x40ULL);
        card->tx_dsc_buffer_host_addr = (card->tx_dsc_buffer_host_addr_tmp & 0xffffffffffffffc0ULL) + 0x40ULL;
        //skb = dev_alloc_skb(SK_BUFF_ALLOC_SIZE + 2);
        //skb_reserve(skb, 2);
        //card->tx_dsc_buffer_ptr = (void *)(skb->data);
        //card->tx_dsc_buffer_ptr = (void *)(((uint64_t)(card->tx_dsc_buffer_ptr) & 0xffffffffffffffc0ULL) + 0x40ULL);
        //card->tx_bk_skb[4] = skb;
        

        skb = dev_alloc_skb(SK_BUFF_ALLOC_SIZE + 2);
        skb_reserve(skb, 2);
        memset(skb->data, 1, 200);
        *(skb->data) = (uint8_t)1;
        card->tx_bk_skb[0] = skb;
        dma_addr = pci_map_single(card->pdev, skb->data, SK_BUFF_ALLOC_SIZE, PCI_DMA_TODEVICE);
        card->tx_bk_dma_addr[0] = dma_addr;
        dsc_l0 = ((uint64_t)pkt_len << 48) + ((uint64_t)port_decoded << 32) + 0xffffffff;
        dsc_l1 = dma_addr;
        *(((uint64_t*)card->tx_dsc_buffer_ptr) + 8 * 0 + 0) = dsc_l0;
        *(((uint64_t*)card->tx_dsc_buffer_ptr) + 8 * 0 + 1) = dsc_l1;
        printk(KERN_INFO "%x %x", (card->tx_bk_skb[0]->data), (card->tx_bk_dma_addr[0]));
        if(pci_dma_mapping_error(card->pdev, dma_addr)){
            printk(KERN_ERR "nf10: dma mapping error");
        }

        skb = dev_alloc_skb(SK_BUFF_ALLOC_SIZE + 2);
        skb_reserve(skb, 2);
        memset(skb->data, 2, 200);
        *(skb->data) = (uint8_t)2;
        card->tx_bk_skb[1] = skb;
        dma_addr = pci_map_single(card->pdev, skb->data, SK_BUFF_ALLOC_SIZE, PCI_DMA_TODEVICE);
        card->tx_bk_dma_addr[1] = dma_addr;
        dsc_l0 = ((uint64_t)pkt_len << 48) + ((uint64_t)port_decoded << 32) + 0xffffffff;
        dsc_l1 = dma_addr;
        *(((uint64_t*)card->tx_dsc_buffer_ptr) + 8 * 1 + 0) = dsc_l0;
        *(((uint64_t*)card->tx_dsc_buffer_ptr) + 8 * 1 + 1) = dsc_l1;
        printk(KERN_INFO "%x %x", (card->tx_bk_skb[1]->data), (card->tx_bk_dma_addr[1]));
        if(pci_dma_mapping_error(card->pdev, dma_addr)){
            printk(KERN_ERR "nf10: dma mapping error");
        }

        skb = dev_alloc_skb(SK_BUFF_ALLOC_SIZE + 2);
        skb_reserve(skb, 2);
        memset(skb->data, 3, 200);
        *(skb->data) = (uint8_t)3;
        card->tx_bk_skb[2] = skb;
        dma_addr = pci_map_single(card->pdev, skb->data, SK_BUFF_ALLOC_SIZE, PCI_DMA_TODEVICE);
        card->tx_bk_dma_addr[2] = dma_addr;
        dsc_l0 = ((uint64_t)pkt_len << 48) + ((uint64_t)port_decoded << 32) + 0xffffffff;
        dsc_l1 = dma_addr;
        *(((uint64_t*)card->tx_dsc_buffer_ptr) + 8 * 2 + 0) = dsc_l0;
        *(((uint64_t*)card->tx_dsc_buffer_ptr) + 8 * 2 + 1) = dsc_l1;
        printk(KERN_INFO "%x %x", (card->tx_bk_skb[2]->data), (card->tx_bk_dma_addr[2]));
        if(pci_dma_mapping_error(card->pdev, dma_addr)){
            printk(KERN_ERR "nf10: dma mapping error");
        }
        
        skb = dev_alloc_skb(SK_BUFF_ALLOC_SIZE + 2);
        skb_reserve(skb, 2);
        *(skb->data) = (uint8_t)4;
        card->tx_bk_skb[3] = skb;
        dma_addr = pci_map_single(card->pdev, skb->data, SK_BUFF_ALLOC_SIZE, PCI_DMA_TODEVICE);
        card->tx_bk_dma_addr[3] = dma_addr;
        //dsc_l0 = ((uint64_t)pkt_len << 48) + ((uint64_t)port_decoded << 32) + 0xffffffff;
        //dsc_l1 = dma_addr;
        printk(KERN_INFO "%x %x", (card->tx_bk_skb[3]->data), (card->tx_bk_dma_addr[3]));
        if(pci_dma_mapping_error(card->pdev, dma_addr)){
            printk(KERN_ERR "nf10: dma mapping error");
        }*/
        

        //dma_addr = pci_map_single(card->pdev, card->tx_bk_skb[4]->data, SK_BUFF_ALLOC_SIZE, PCI_DMA_TODEVICE);
        //card->tx_bk_dma_addr[4] = dma_addr;
        //card->tx_dsc_buffer_host_addr = (dma_addr & 0xffffffffffffffc0ULL) + 0x40;
        //printk(KERN_INFO "%x %x", (card->tx_bk_skb[4]->data), (card->tx_bk_dma_addr[4]));
        //if(pci_dma_mapping_error(card->pdev, dma_addr)){
        //    printk(KERN_ERR "nf10: dma mapping error");
        //}
        
        /*
        doorbell_add_class(card, card->tx_dsc_buffer_host_addr, card->tx_dsc_buffer_host_mask);
        doorbell_set_rate(card, 0, 1);
        doorbell_set_tokens_max(card, 0, 0xffffffff);
        msleep(1000);
        doorbell_add_dsc(card, 0, card->tx_bk_dma_addr[0], 8, pkt_len, 3);
        */
/*
    mb();
    *(((uint64_t*)card->tx_doorbell) + 8 * 0 + 0) = ((uint64_t)500 << 32);
    *(((uint64_t*)card->tx_doorbell) + 8 * 0 + 1) = card->tx_dsc_buffer_host_addr;
    *(((uint64_t*)card->tx_doorbell) + 8 * 1 + 0) = (0x40ULL << 32) + card->tx_dsc_buffer_host_mask;
    *(((uint64_t*)card->tx_doorbell) + 8 * 1 + 1) = (0xc0ULL << 64);
    *(((uint64_t*)card->tx_doorbell) + 8 * 2 + 0) = card->tx_bk_dma_addr[3];
    *(((uint64_t*)card->tx_doorbell) + 8 * 2 + 1) = (port_decoded << 96) + (uint64_t)pkt_len;
    mb();*/
        card->debug = 0;
        for(i=0;i<500;i++){
            printk(KERN_EMERG "add class %d\n", i);
            nicpic_add_class(card, 0xffffULL, 12800, 0xbb80000);
        }
        //printk(KERN_INFO "reset: %d\n", *(((uint64_t*)card->cfg_addr)+30));
        printk(KERN_INFO "nf10: device ready\n");
        return ret;
    }

 // error out
 err_out_free_private2:
    if(card->tx_bk_dma_addr) kfree(card->tx_bk_dma_addr);
    if(card->tx_bk_skb) kfree(card->tx_bk_skb);
    if(card->tx_bk_size) kfree(card->tx_bk_size);
    if(card->tx_bk_port) kfree(card->tx_bk_port);
    if(card->rx_bk_dma_addr) kfree(card->rx_bk_dma_addr);
    if(card->rx_bk_skb) kfree(card->rx_bk_skb);
    if(card->rx_bk_size) kfree(card->rx_bk_size);
    pci_free_consistent(pdev, card->tx_dne_mask+1, card->host_tx_dne_ptr, card->host_tx_dne_dma);
    pci_free_consistent(pdev, card->rx_dne_mask+1, card->host_rx_dne_ptr, card->host_rx_dne_dma);
    pci_free_consistent(pdev, card->tx_doorbell_dne_mask+1, card->host_tx_doorbell_dne_ptr, card->host_tx_doorbell_dne_dma);
 err_out_iounmap:
    if(card->tx_doorbell) iounmap(card->tx_doorbell);
    if(card->rx_dsc) iounmap(card->rx_dsc);
    if(card->cfg_addr)   iounmap(card->cfg_addr);
	pci_set_drvdata(pdev, NULL);
	kfree(card);
 err_out_release_mem_region2:
	release_mem_region(pci_resource_start(pdev, 2), pci_resource_len(pdev, 2));
 err_out_release_mem_region1:
	release_mem_region(pci_resource_start(pdev, 0), pci_resource_len(pdev, 0));
 err_out_msi:
    pci_disable_msi(pdev);
 err_out_disable_device:
	pci_disable_device(pdev);
 err_out_none:
	return ret;
}

static void __devexit nf10_remove(struct pci_dev *pdev){
    struct nf10_card *card;
    int i, j;

    // free private data
    printk(KERN_INFO "nf10: releasing private memory\n");
    card = (struct nf10_card*)pci_get_drvdata(pdev);

    //doorbell_stop_class(card, 0);
    //doorbell_delete_class(card);
    /*
    for(i=0;i<4;i++)
    {
        printk(KERN_INFO "%x %x", (card->tx_bk_skb[i]->data), (card->tx_bk_dma_addr[i]));
        pci_unmap_single(card->pdev, card->tx_bk_dma_addr[i], SK_BUFF_ALLOC_SIZE, PCI_DMA_TODEVICE);
        dev_kfree_skb_any(card->tx_bk_skb[i]);
    }*/

    //nicpic_delete_class(card);
    //nicpic_delete_class(card);
    //msleep(1000);
    kfree(msg);
    for(j=0; j<card->class_num; j++)
    {
        for(i=atomic64_read(&card->dsc_buffs[j]->head); i<card->dsc_buffs[j]->tail; i++){
        pci_unmap_single(card->pdev, card->dsc_buffs[j]->pkt_physical_addr[i],
                         card->dsc_buffs[j]->skb[i]->len, PCI_DMA_TODEVICE);
        dev_kfree_skb_any(card->dsc_buffs[j]->skb[i]);
        }
        kfree(card->dsc_buffs[j]->skb);
        kfree(card->dsc_buffs[j]->pkt_physical_addr);
        pci_free_consistent(card->pdev, card->dsc_buffs[j]->mask+65,
                            card->dsc_buffs[j]->ptr_ori,
                            card->dsc_buffs[j]->physical_addr_ori);
        kfree(card->dsc_buffs[j]);
    }

    if(card){

        nf10fops_remove(pdev, card);
        nf10iface_remove(pdev, card);

        if(card->cfg_addr) iounmap(card->cfg_addr);

        if(card->tx_doorbell) iounmap(card->tx_doorbell);
        if(card->rx_dsc) iounmap(card->rx_dsc);

        pci_free_consistent(pdev, card->tx_dne_mask+1, card->host_tx_dne_ptr, card->host_tx_dne_dma);
        pci_free_consistent(pdev, card->rx_dne_mask+1, card->host_rx_dne_ptr, card->host_rx_dne_dma);
        pci_free_consistent(pdev, card->tx_doorbell_dne_mask+1, card->host_tx_doorbell_dne_ptr, card->host_tx_doorbell_dne_dma);
        //pci_free_consistent(pdev, card->tx_dsc_buffer_host_mask+1, card->tx_dsc_buffer_ptr_tmp, card->tx_dsc_buffer_host_addr_tmp);

        if(card->tx_bk_dma_addr) kfree(card->tx_bk_dma_addr);
        if(card->tx_bk_skb) kfree(card->tx_bk_skb);
        if(card->tx_bk_size) kfree(card->tx_bk_size);
        if(card->tx_bk_port) kfree(card->tx_bk_port);
        if(card->rx_bk_dma_addr) kfree(card->rx_bk_dma_addr);
        if(card->rx_bk_skb) kfree(card->rx_bk_skb);
        if(card->rx_bk_size) kfree(card->rx_bk_size);
        
        kfree(card);
    }

    pci_set_drvdata(pdev, NULL);

    // release memory
    printk(KERN_INFO "nf10: releasing mem region\n");
	release_mem_region(pci_resource_start(pdev, 0), pci_resource_len(pdev, 0));
	release_mem_region(pci_resource_start(pdev, 2), pci_resource_len(pdev, 2));

    // disabling device
    printk(KERN_INFO "nf10: disabling device\n");
    pci_disable_msi(pdev);
    pci_disable_device(pdev);
}

pci_ers_result_t nf10_pcie_error(struct pci_dev *dev, enum pci_channel_state state){
    printk(KERN_ALERT "nf10: PCIe error: %d\n", state);
    return PCI_ERS_RESULT_RECOVERED;
}

static struct pci_error_handlers pcie_err_handlers = {
    .error_detected = nf10_pcie_error
};

static struct pci_driver pci_driver = {
	.name = "nf10",
	.id_table = pci_id,
	.probe = nf10_probe,
	.remove = __devexit_p(nf10_remove),
    .err_handler = &pcie_err_handlers
};

static ssize_t device_read(struct file *filp, char __user *buffer, size_t length, loff_t *offset)
{
  	return simple_read_from_buffer(buffer, length, offset, msg, 8192);
}


static ssize_t device_write(struct file *filp, const char __user *buff, size_t len, loff_t *off)
{
	return 0;
}

static struct file_operations fops = {
	.read = device_read, 
	.write = device_write,
};

static int __init nf10_init(void)
{
	printk(KERN_INFO "nf10: module loaded\n");

        major = register_chrdev(0, "my_device", &fops);
	if (major < 0) {
     		printk ("Registering the character device failed with %d\n", major);
	     	return major;
	}
	printk("cdev example: assigned major: %d\n", major);
	printk(KERN_EMERG "create node with mknod /dev/cdev_example c %d 0\n", major);

        msg = (char *)kmalloc(8192, GFP_KERNEL);

        memset(msg, 'X', 10);

	return pci_register_driver(&pci_driver);
}

static void __exit nf10_exit(void)
{
    pci_unregister_driver(&pci_driver);
	unregister_chrdev(major, "my_device");
	printk(KERN_INFO "nf10: module unloaded\n");
}


module_init(nf10_init);
module_exit(nf10_exit);



