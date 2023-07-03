###############################################################################
#   Read in product name from registered licenses
#
# Copyright 2017, IBM Corporation
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################

reg_licenses=""

echo "" > license_text
lic_txt_count=`/opt/ibm/db2/V*/adm/db2licm -l | grep "Product name" | cut -d: -f2 | sed -e 's/"//g'`
if [ `echo $lic_txt_count | wc -l` > 1 ]; then
	/opt/ibm/db2/V*/adm/db2licm -l | grep "Product name" | cut -d: -f2 | sed -e 's/"//g' | while read -r line
	do
		per_product=`/opt/ibm/db2/V*/adm/db2licm -l | grep -A5 "$line"`
		if  [[ $per_product =~ "License not registered" ]]; then
			continue
		else
			type=`/opt/ibm/db2/V*/adm/db2licm -l | grep -A5 "$line" | grep "License type" | cut -d: -f2 | sed 's/"//g' | tr -d ' '`
			reg_licenses+=${line}"(${type})"
			echo "${line} (${type})   " >> license_text
		fi
	done
fi

#echo $reg_licenses
cat license_text
