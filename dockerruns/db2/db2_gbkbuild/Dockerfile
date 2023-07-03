FROM ibmcom/db2:11.5.8.0

RUN localedef -f GBK -i zh_CN /usr/lib/locale/zh_CN.GBK && localedef -f GBK -i zh_CN zh_CN.GBK
#RUN localedef -f GBK -i C /usr/lib/locale/C.GBK && localedef -f GBK -i C C.GBK
#RUN echo "LANG=\"C.GBK\"" > /etc/sysconfig/i18n
#COPY db2_setup/include/db2_common_functions /var/db2_setup/include/db2_common_functions
COPY db2_common_functions /var/db2_setup/include/db2_common_functions
