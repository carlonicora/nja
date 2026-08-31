SURVEY="$NJA_SCRIPTS_DIR/nja-fleet-survey.sh"
NODE_COUNT='let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).members.length))'
NODE_ELIG='let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).members.filter(m=>m.eligible).length))'

fleet="$(t_mkfleet 3)"
export NJA_FLEET_HOME="$fleet/.state"

out="$(bash "$SURVEY" --roots "$fleet" --json 2>/dev/null)"
t_assert_exit 0 "survey succeeds on a healthy fleet" -- bash "$SURVEY" --roots "$fleet" --json
t_assert_contains "$out" '"member-1"' "roster JSON names member-1"
t_assert_contains "$out" '"member-3"' "roster JSON names member-3"
t_assert_eq "3" "$(printf '%s' "$out" | node -e "$NODE_COUNT")" "roster has 3 members"
t_assert_eq "3" "$(printf '%s' "$out" | node -e "$NODE_ELIG")" "all 3 are eligible"
t_assert_not_contains "$out" 'nestjs-neo4jsonapi.git' "bare library origins are not members"

printf 'dirt\n' > "$fleet/member-2/scratch.txt"
out2="$(bash "$SURVEY" --roots "$fleet" --json)"
t_assert_eq "2" "$(printf '%s' "$out2" | node -e "$NODE_ELIG")" "the dirty member is ineligible"
t_assert_eq "3" "$(printf '%s' "$out2" | node -e "$NODE_COUNT")" "the dirty member is still listed"
t_assert_contains "$out2" "root tree dirty" "the reason travels with the member"
rm -f "$fleet/member-2/scratch.txt"

i=2
while [ "$i" -le 3 ]; do
  s="$fleet/member-$i/packages/nestjs-neo4jsonapi"
  printf '// fork %s\n' "$i" >> "$s/package.json"
  git -C "$s" -c user.email=t@t -c user.name=t commit -aqm "fork $i" >/dev/null 2>&1
  i=$((i + 1))
done
t_assert_exit 3 "a 3-way SHA split exits 3" -- bash "$SURVEY" --roots "$fleet" --json
t_assert_contains "$(bash "$SURVEY" --roots "$fleet" 2>&1)" "forked" "the forked message names the condition"

rm -rf "$fleet"
unset NJA_FLEET_HOME

empty="$(cd "$(mktemp -d -t nja-empty)" && pwd -P)"
t_assert_exit 2 "an empty root exits 2" -- bash "$SURVEY" --roots "$empty"
rm -rf "$empty"

t_assert_exit 1 "a bare --roots with no value exits 1" -- bash "$SURVEY" --roots
t_assert_exit 1 "an option-like --roots value exits 1" -- bash "$SURVEY" --roots --json
