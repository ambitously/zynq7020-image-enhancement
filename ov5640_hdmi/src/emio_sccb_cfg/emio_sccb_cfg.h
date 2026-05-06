/*
 * emio_sccb_cfg.h
 *
 *  Created on: 2022Äê3ÔÂ22ÈÕ
 *      Author: zhaoj
 */

//#ifndef SRC_EMIO_SCCB_CFG_EMIO_SCCB_CFG_H_
//#define SRC_EMIO_SCCB_CFG_EMIO_SCCB_CFG_H_

#include"xgpiops.h"
#include"sleep.h"

#ifndef sccb_EMIO_CFG_
#define sccb_EMIO_CFG_

#define EMIO_SCL_NUM 54
#define EMIO_SDA_NUM 55

void emio_init(void);
void sccb_start(void);
void sccb_stop(void);
void sccb_ack(void);
void sccb_send_byte(u8 txd);
u8  sccb_rece_byte(void);





#endif /* SRC_EMIO_SCCB_CFG_EMIO_SCCB_CFG_H_ */
