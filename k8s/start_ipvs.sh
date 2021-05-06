# 临时生效
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- ip_vs_nq 
modprobe -- nf_conntrack_ipv4
# 永久生效
#cat > /etc/sysconfig/modules/ipvs.modules <<EOF
#modprobe -- ip_vs
#modprobe -- ip_vs_rr
#modprobe -- ip_vs_wrr
#modprobe -- ip_vs_sh
#modprobe -- ip_vs_nq 
#modprobe -- nf_conntrack_ipv4
#EOF
