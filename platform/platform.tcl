# 
# Usage: To re-create this platform project launch xsct with below options.
# xsct D:\IEEE\zdyz_copy\platform\platform.tcl
# 
# OR launch xsct and run below command.
# source D:\IEEE\zdyz_copy\platform\platform.tcl
# 
# To create the platform in a different location, modify the -out option of "platform create" command.
# -out option specifies the output directory of the platform project.

platform create -name {platform}\
-hw {D:\IEEE\zdyz_copy\V2_ov5640_hdmi\design_1_wrapper.xsa}\
-proc {ps7_cortexa9_0} -os {standalone} -fsbl-target {psu_cortexa53_0} -out {D:/IEEE/zdyz_copy}

platform write
platform generate -domains 
platform active {platform}
platform generate
platform clean
platform generate
platform config -updatehw {D:/IEEE/zdyz_copy/V2_ov5640_hdmi/design_1_wrapper.xsa}
platform generate -domains 
platform config -updatehw {D:/IEEE/zdyz_copy/V2_ov5640_hdmi/design_1_wrapper.xsa}
platform generate -domains 
platform config -updatehw {D:/IEEE/zdyz_copy/V2_ov5640_hdmi/design_1_wrapper.xsa}
platform generate -domains 
platform config -updatehw {D:/IEEE/zdyz_copy/V2_ov5640_hdmi/design_1_wrapper.xsa}
platform generate -domains 
platform config -updatehw {D:/IEEE/zdyz_copy/V2_ov5640_hdmi/design_1_wrapper.xsa}
platform generate -domains 
platform config -updatehw {D:/IEEE/zdyz_copy/V2_ov5640_hdmi/design_1_wrapper.xsa}
platform generate -domains 
platform config -updatehw {D:/IEEE/zdyz_copy/V2_ov5640_hdmi/design_1_wrapper.xsa}
platform generate -domains 
platform config -updatehw {D:/IEEE/zdyz_copy/V2_ov5640_hdmi/design_1_wrapper.xsa}
platform generate -domains 
platform active {platform}
