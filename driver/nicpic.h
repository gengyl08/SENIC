#ifndef NICPIC_H
#define NICPIC_H

#include "nf10driver.h"

void doorbell_add_class(struct nf10_card *card, uint64_t dsc_buffer_host_addr, uint64_t dsc_buffer_mask);
void doorbell_set_rate(struct nf10_card *card, uint64_t class_index, uint64_t rate);
void doorbell_set_tokens_max(struct nf10_card *card, uint64_t class_index, uint64_t tokens_max);
void doorbell_add_dsc(struct nf10_card *card, uint64_t class_index, uint64_t pkt_host_addr,
                      uint64_t pkt_port_short, uint64_t pkt_len, uint64_t dsc_tail_index);
void doorbell_stop_class(struct nf10_card *card, uint64_t class_index);
void doorbell_delete_class(struct nf10_card *card);

int nicpic_add_class(struct nf10_card *card, uint64_t buff_mask, uint64_t rate, uint64_t tokens_max);
void nicpic_delete_class(struct nf10_card *card);
void nicpic_start_class(struct nf10_card *card, uint64_t class_index, uint64_t pkt_len);

#endif
