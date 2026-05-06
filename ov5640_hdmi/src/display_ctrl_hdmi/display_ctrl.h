/*
 * display_ctrl.h
 *
 *  Created on: 2022Äê3ÔÂ22ÈÕ
 *      Author: zhaoj
 */

#ifndef DISPLAY_CTRL_H_
#define DISPLAY_CTRL_H_

/* ------------------------------------------------------------ */
/*				Include File Definitions						*/
/* ------------------------------------------------------------ */

#include "xil_types.h"
#include "xaxivdma.h"
#include "xvtc.h"
#include "../dynclk/dynclk.h"
#include "lcd_modes.h"
//#include "xgpio.h"

/* ------------------------------------------------------------ */
/*					Miscellaneous Declarations					*/
/* ------------------------------------------------------------ */

#define BIT_DISPLAY_RED 16
#define BIT_DISPLAY_GREEN 8
#define BIT_DISPLAY_BLUE 0

/*
 * This driver currently supports frames.
 */
#define DISPLAY_NUM_FRAMES 1

/* ------------------------------------------------------------ */
/*					General Type Declarations					*/
/* ------------------------------------------------------------ */

typedef enum {
	DISPLAY_STOPPED = 0,
	DISPLAY_RUNNING = 1
} DisplayState;

typedef struct {
		u32 	 dynClkAddr;/*Physical Base address of the dynclk core*/
		XVtc vtc;		 	/*VTC driver struct*/
		VideoMode vMode; 	/*Current Video mode*/
		double pxlFreq;		/* Frequency of clock currently being generated */
		DisplayState state; /* Indicates if the Display is currently running */
} DisplayCtrl;

/* ------------------------------------------------------------ */
/*					Procedure Declarations						*/
/* ------------------------------------------------------------ */

int DisplayStop(DisplayCtrl *dispPtr);
int DisplayStart(DisplayCtrl *dispPtr);
int DisplayInitialize(DisplayCtrl *dispPtr,                 u16 vtcId, u32 dynClkAddr);
int DisplaySetMode(DisplayCtrl *dispPtr, const VideoMode *newMode);
int DisplayChangeFrame(DisplayCtrl *dispPtr, u32 frameIndex);

//u16 LTDC_PanelID_Read(XGpio * axi_gpio_inst, unsigned chanel);

/* ------------------------------------------------------------ */

/************************************************************************/



#endif /* SRC_DISPLAY_CTRL_HDMI_DISPLAY_CTRL_H_ */
