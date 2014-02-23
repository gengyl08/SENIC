#include <linux/pci.h>
#include <linux/spinlock.h>
#include "nicpic.h"
#define SK_BUFF_ALLOC_SIZE  1533

static DEFINE_SPINLOCK(doorbell_lock);

void doorbell_add_class(struct nf10_card *card, uint64_t dsc_buffer_host_addr, uint64_t dsc_buffer_mask)
{
    unsigned long flags;
    uint64_t dsc_l0, dsc_l1;
    uint64_t inst = 1;
    uint64_t class_index = 0;
    uint64_t doorbell_addr = 0, doorbell_index = 0;
    uint64_t space;
    uint64_t doorbell_head;

    spin_lock_irqsave(&doorbell_lock, flags);

    do{
        mb();
        doorbell_head = *(((uint64_t*)card->cfg_addr)+52);
        mb();
        if((doorbell_head>>6)<=((card->mem_tx_doorbell.wr_ptr)>>6))
            space = ((card->mem_tx_doorbell.mask+1)>>6)+((doorbell_head>>6))-((card->mem_tx_doorbell.wr_ptr)>>6);
        else
            space = ((doorbell_head>>6))-((card->mem_tx_doorbell.wr_ptr)>>6);
        if(net_ratelimit()) printk(KERN_EMERG "head: %d, tail: %d, space: %d", doorbell_head, card->mem_tx_doorbell.wr_ptr,  space);
    } while(space<31);

    doorbell_addr = card->mem_tx_doorbell.wr_ptr;
    card->mem_tx_doorbell.wr_ptr = (doorbell_addr + 64) & card->mem_tx_doorbell.mask;
    doorbell_index = doorbell_addr/64;

    dsc_l0 = (dsc_buffer_mask<<32) + (class_index<<6) + inst;
    dsc_l1 = dsc_buffer_host_addr;

    mb();
    *(((uint64_t*)card->tx_doorbell) + 8 * doorbell_index + 0) = dsc_l0;
    *(((uint64_t*)card->tx_doorbell) + 8 * doorbell_index + 1) = dsc_l1;
    mb();

    spin_unlock_irqrestore(&doorbell_lock, flags);
}

void doorbell_set_rate(struct nf10_card *card, uint64_t class_index, uint64_t rate)
{
    unsigned long flags;
    uint64_t dsc_l0, dsc_l1;
    uint64_t inst = 2;
    uint64_t doorbell_addr = 0, doorbell_index = 0;
    uint64_t space;
    uint64_t doorbell_head;

    spin_lock_irqsave(&doorbell_lock, flags);

    do{
        mb();
        doorbell_head = *(((uint64_t*)card->cfg_addr)+52);
        mb();
        if((doorbell_head>>6)<=((card->mem_tx_doorbell.wr_ptr)>>6))
            space = ((card->mem_tx_doorbell.mask+1)>>6)+((doorbell_head>>6))-((card->mem_tx_doorbell.wr_ptr)>>6);
        else
            space = ((doorbell_head>>6))-((card->mem_tx_doorbell.wr_ptr)>>6);
        if(net_ratelimit()) printk(KERN_EMERG "head: %d, tail: %d, space: %d", doorbell_head, card->mem_tx_doorbell.wr_ptr,  space);
    } while(space<31);

    doorbell_addr = card->mem_tx_doorbell.wr_ptr;
    card->mem_tx_doorbell.wr_ptr = (doorbell_addr + 64) & card->mem_tx_doorbell.mask;
    doorbell_index = doorbell_addr/64;

    dsc_l0 = (class_index<<6) + inst;
    dsc_l1 = rate;

    mb();
    *(((uint64_t*)card->tx_doorbell) + 8 * doorbell_index + 0) = dsc_l0;
    *(((uint64_t*)card->tx_doorbell) + 8 * doorbell_index + 1) = dsc_l1;
    mb();

    spin_unlock_irqrestore(&doorbell_lock, flags);
}

void doorbell_set_tokens_max(struct nf10_card *card, uint64_t class_index, uint64_t tokens_max)
{
    unsigned long flags;
    uint64_t dsc_l0, dsc_l1;
    uint64_t inst = 3;
    uint64_t doorbell_addr = 0, doorbell_index = 0;
    uint64_t space;
    uint64_t doorbell_head;

    spin_lock_irqsave(&doorbell_lock, flags);

    do{
        mb();
        doorbell_head = *(((uint64_t*)card->cfg_addr)+52);
        mb();
        if((doorbell_head>>6)<=((card->mem_tx_doorbell.wr_ptr)>>6))
            space = ((card->mem_tx_doorbell.mask+1)>>6)+((doorbell_head>>6))-((card->mem_tx_doorbell.wr_ptr)>>6);
        else
            space = ((doorbell_head>>6))-((card->mem_tx_doorbell.wr_ptr)>>6);
        if(net_ratelimit()) printk(KERN_EMERG "head: %d, tail: %d, space: %d", doorbell_head, card->mem_tx_doorbell.wr_ptr,  space);
    } while(space<31);

    doorbell_addr = card->mem_tx_doorbell.wr_ptr;
    card->mem_tx_doorbell.wr_ptr = (doorbell_addr + 64) & card->mem_tx_doorbell.mask;
    doorbell_index = doorbell_addr/64;

    dsc_l0 = (class_index<<6) + inst;
    dsc_l1 = tokens_max;

    mb();
    *(((uint64_t*)card->tx_doorbell) + 8 * doorbell_index + 0) = dsc_l0;
    *(((uint64_t*)card->tx_doorbell) + 8 * doorbell_index + 1) = dsc_l1;
    mb();

    spin_unlock_irqrestore(&doorbell_lock, flags);
}

void doorbell_add_dsc(struct nf10_card *card, uint64_t class_index, uint64_t pkt_host_addr,
                      uint64_t pkt_port_short, uint64_t pkt_len, uint64_t dsc_tail_index)
{
    unsigned long flags;
    uint64_t dsc_l0, dsc_l1;
    uint64_t inst = 4;
    uint64_t doorbell_addr = 0, doorbell_index = 0;
    uint64_t space;
    uint64_t doorbell_head;
    int count = 0;
    spin_lock_irqsave(&doorbell_lock, flags);

    do{
        //if(count>20){
        //    spin_unlock_irqrestore(&doorbell_lock, flags);
        //    board_restart(card);
        //    printk(KERN_EMERG "board restart!");
        //    msleep(10000);
        //    return;
        //}
        //count++;
        mb();
        doorbell_head = *(((uint64_t*)card->cfg_addr)+52);
        mb();
        if((doorbell_head>>6)<=((card->mem_tx_doorbell.wr_ptr)>>6))
            space = ((card->mem_tx_doorbell.mask+1)>>6)+((doorbell_head>>6))-((card->mem_tx_doorbell.wr_ptr)>>6);
        else
            space = ((doorbell_head>>6))-((card->mem_tx_doorbell.wr_ptr)>>6);
        if(net_ratelimit()) printk(KERN_EMERG "head: %d, tail: %d, space: %d", doorbell_head, card->mem_tx_doorbell.wr_ptr,  space);
    } while(space<31);

    doorbell_addr = card->mem_tx_doorbell.wr_ptr;
    card->mem_tx_doorbell.wr_ptr = (doorbell_addr + 64) & card->mem_tx_doorbell.mask;
    doorbell_index = doorbell_addr/64;

    dsc_l0 = (dsc_tail_index<<38) + (pkt_port_short<<32) + (pkt_len<<16) + (class_index<<6) + inst;
    dsc_l1 = pkt_host_addr;

    mb();
    *(((uint64_t*)card->tx_doorbell) + 8 * doorbell_index + 0) = dsc_l0;
    *(((uint64_t*)card->tx_doorbell) + 8 * doorbell_index + 1) = dsc_l1;
    mb();

    spin_unlock_irqrestore(&doorbell_lock, flags);
    return;
}

void doorbell_stop_class(struct nf10_card *card, uint64_t class_index)
{
    unsigned long flags;
    uint64_t dsc_l0, dsc_l1;
    uint64_t inst = 5;
    uint64_t doorbell_addr = 0, doorbell_index = 0;
    uint64_t space;
    uint64_t doorbell_head;

    spin_lock_irqsave(&doorbell_lock, flags);

    do{
        mb();
        doorbell_head = *(((uint64_t*)card->cfg_addr)+52);
        mb();
        if((doorbell_head>>6)<=((card->mem_tx_doorbell.wr_ptr)>>6))
            space = ((card->mem_tx_doorbell.mask+1)>>6)+((doorbell_head>>6))-((card->mem_tx_doorbell.wr_ptr)>>6);
        else
            space = ((doorbell_head>>6))-((card->mem_tx_doorbell.wr_ptr)>>6);
    } while(space<31);

    doorbell_addr = card->mem_tx_doorbell.wr_ptr;
    card->mem_tx_doorbell.wr_ptr = (doorbell_addr + 64) & card->mem_tx_doorbell.mask;
    doorbell_index = doorbell_addr/64;

    dsc_l0 = (class_index<<6) + inst;
    dsc_l1 = 0xffffffffffffffffULL;

    mb();
    *(((uint64_t*)card->tx_doorbell) + 8 * doorbell_index + 0) = dsc_l0;
    *(((uint64_t*)card->tx_doorbell) + 8 * doorbell_index + 1) = dsc_l1;
    mb();

    spin_unlock_irqrestore(&doorbell_lock, flags);
}

void doorbell_delete_class(struct nf10_card *card)
{
    unsigned long flags;
    uint64_t dsc_l0, dsc_l1;
    uint64_t inst = 6;
    uint64_t class_index = 0;
    uint64_t doorbell_addr = 0, doorbell_index = 0;
    uint64_t space;
    uint64_t doorbell_head;

    spin_lock_irqsave(&doorbell_lock, flags);

    do{
        mb();
        doorbell_head = *(((uint64_t*)card->cfg_addr)+52);
        mb();
        if((doorbell_head>>6)<=((card->mem_tx_doorbell.wr_ptr)>>6))
            space = ((card->mem_tx_doorbell.mask+1)>>6)+((doorbell_head>>6))-((card->mem_tx_doorbell.wr_ptr)>>6);
        else
            space = ((doorbell_head>>6))-((card->mem_tx_doorbell.wr_ptr)>>6);
    } while(space<31);

    doorbell_addr = card->mem_tx_doorbell.wr_ptr;
    card->mem_tx_doorbell.wr_ptr = (doorbell_addr + 64) & card->mem_tx_doorbell.mask;
    doorbell_index = doorbell_addr/64;

    dsc_l0 = (class_index<<6) + inst;
    dsc_l1 = 0xffffffffffffffffULL;

    mb();
    *(((uint64_t*)card->tx_doorbell) + 8 * doorbell_index + 0) = dsc_l0;
    *(((uint64_t*)card->tx_doorbell) + 8 * doorbell_index + 1) = dsc_l1;
    mb();

    spin_unlock_irqrestore(&doorbell_lock, flags);
}

int nicpic_add_class(struct nf10_card *card, uint64_t buff_mask, uint64_t rate, uint64_t tokens_max)
{
    int class_index;

    class_index = card->class_num;
    card->class_num++;
    card->dsc_buffs[class_index] = (struct dsc_buff*)kmalloc(sizeof(struct dsc_buff), GFP_KERNEL);
    card->dsc_buffs[class_index]->class_index = class_index;
    atomic64_set(&card->dsc_buffs[class_index]->head, 0);
    card->dsc_buffs[class_index]->tail = 0;
    card->dsc_buffs[class_index]->mask = buff_mask;
    //card->dsc_buffs[class_index]->rate = rate;
    //card->dsc_buffs[class_index]->tokens_max = tokens_max;

    card->dsc_buffs[class_index]->ptr_ori = pci_alloc_consistent(card->pdev, buff_mask+1+64, &(card->dsc_buffs[class_index]->physical_addr_ori));
    if(card->dsc_buffs[class_index]->ptr_ori == NULL)
    {
        card->class_num--;
        return 0;
    }
    card->dsc_buffs[class_index]->ptr = (void *)(((uint64_t)(card->dsc_buffs[class_index]->ptr_ori) & 0xffffffffffffffc0ULL) + 0x40ULL);
    card->dsc_buffs[class_index]->physical_addr = (card->dsc_buffs[class_index]->physical_addr_ori & 0xffffffffffffffc0ULL) + 0x40ULL;
    //card->dsc_buffs[class_index]->skb = (struct sk_buff**)kmalloc((buff_mask+1)*sizeof(struct sk_buff*), GFP_KERNEL);
    //card->dsc_buffs[class_index]->pkt_physical_addr = (uint64_t *)kmalloc((buff_mask+1)*sizeof(uint64_t), GFP_KERNEL);

    doorbell_add_class(card, card->dsc_buffs[class_index]->physical_addr, buff_mask);
    doorbell_set_rate(card, class_index, rate);
    doorbell_set_tokens_max(card, class_index, tokens_max);

    return 1;
}

void nicpic_delete_class(struct nf10_card *card)
{
        doorbell_stop_class(card, card->class_num - 1);
        doorbell_delete_class(card);
}
/*
void nicpic_start_class(struct nf10_card *card, uint64_t class_index, uint64_t pkt_len)
{
    struct sk_buff *skb;
    uint64_t dma_addr;
    uint64_t dsc_l0, dsc_l1;
    uint64_t port_decoded = 0x4080;
    int i;

    skb = dev_alloc_skb(SK_BUFF_ALLOC_SIZE + 2);
    skb_reserve(skb, 2);
    *((uint16_t *)(skb->data)) = (uint16_t)(class_index + 1);
    memset((void *)skb->data, (uint8_t)(class_index + 1), pkt_len);
    card->dsc_buffs[class_index]->skb = skb;
    dma_addr = pci_map_single(card->pdev, skb->data, SK_BUFF_ALLOC_SIZE, PCI_DMA_TODEVICE);
    card->dsc_buffs[class_index]->pkt_physical_addr = dma_addr;
    card->dsc_buffs[class_index]->pkt_len = pkt_len;
    dsc_l0 = (pkt_len << 48) + ((uint64_t)port_decoded << 32) + 0xffffffff;
    dsc_l1 = dma_addr;

    for(i=0; i<=((card->dsc_buffs[class_index]->mask)>>6); i++)
    {
        *(((uint64_t*)card->dsc_buffs[class_index]->ptr) + 8 * i + 0) = dsc_l0;
        *(((uint64_t*)card->dsc_buffs[class_index]->ptr) + 8 * i + 1) = dsc_l1;
    }
    card->dsc_buffs[class_index]->tail = ((card->dsc_buffs[class_index]->mask)>>6);
    doorbell_add_dsc(card, class_index, card->dsc_buffs[class_index]->pkt_physical_addr, 0x8ULL, pkt_len, card->dsc_buffs[class_index]->tail);
    //printk(KERN_INFO "packet dma addr: %x\n", dma_addr);
    //printk(KERN_INFO "packet first byte: %d\n", *((uint8_t *)skb->data));
}*/

void nicpic_add_dsc(struct nf10_card *card, uint64_t class_index)
{   
    if(atomic64_read(&card->dsc_buffs[class_index]->head) == 0)
        card->dsc_buffs[class_index]->tail = ((card->dsc_buffs[class_index]->mask)>>6);
    else
        card->dsc_buffs[class_index]->tail = atomic64_read(&card->dsc_buffs[class_index]->head) - 1;
    
    //printk(KERN_EMERG "begin adding doorbell\n");
    doorbell_add_dsc(card, class_index, card->dsc_buffs[class_index]->pkt_physical_addr, 0x1ULL,
                     card->dsc_buffs[class_index]->pkt_len, card->dsc_buffs[class_index]->tail);
    //printk(KERN_EMERG "finish adding doorbell\n");
}

