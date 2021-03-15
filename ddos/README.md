## Populate tables

te = table_entry["MyIngress.throttle"](action="MyIngress.throttle_packets")

te.match['do_drop']="0"

te.action['p']="2"

te.action['thresh']="10"

te.insert()

te = table_entry["MyIngress.drop_table"](action="MyIngress.drop")

te.match['do_drop']="1"

te.insert()

## Testing
