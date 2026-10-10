class_name MultiplayerLoanPanel
extends VBoxContainer
## A normal Budget tab. Displayed terms are never editable after acceptance.

var coop_ref: WeakRef
var coop: ApplicationMultiplayer:
	get:
		return coop_ref.get_ref()
var counterpart: OptionButton
var amount: SpinBox
var rows: VBoxContainer
var signature := ""

func setup(owner: ApplicationMultiplayer) -> void:
	coop_ref = weakref(owner)
	name = "Player loans"
	var help := ApplicationMultiplayer.label(self, tr("Choose the lender and principal. The game sets the bond rate. Interest settles with the annual budget; there is no maturity date. Repay when funds permit."))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var form := GridContainer.new()
	form.columns = 2
	add_child(form)
	ApplicationMultiplayer.label(form, tr("Lender"))
	counterpart = OptionButton.new()
	form.add_child(counterpart)
	amount = field(form, tr("Principal"), 10000, 500000, 10000)
	amount.step = 10000
	ApplicationMultiplayer.button(self, tr("Confirm and send proposal"), func() -> void:
		if counterpart.selected >= 0:
			coop.session.request({"kind": "loan_offer", "seat": counterpart.get_item_metadata(counterpart.selected),
				"amount": int(amount.value)}))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	coop.session.state_received.connect(update)
	update(coop.session.latest)

func field(parent: Control, caption: String, minimum: int, maximum: int, value: int) -> SpinBox:
	ApplicationMultiplayer.label(parent, caption)
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.value = value
	parent.add_child(input)
	return input

func update(state: Dictionary) -> void:
	var tabs := get_parent() as TabContainer
	if tabs == null:
		return
	var available: bool = state.get("mode") in ["shared", "region"]
	tabs.set_tab_hidden(get_index(), not available)
	tabs.set_tab_title(get_index(), tr("Player loans"))
	if not available:
		return
	var players: Array = state.get("roster", [])
	var names := {}
	for player: Dictionary in players:
		names[player.id] = "%s · %s" % [player.name, player.city]
	var key := JSON.stringify([names, state.get("loans", [])])
	if key == signature:
		return
	signature = key
	var selected: Variant = counterpart.get_item_metadata(counterpart.selected) if counterpart.selected >= 0 else ""
	counterpart.clear()
	var own := coop.session.token.sha256_text()
	for id: String in names:
		if id == own:
			continue
		counterpart.add_item(names[id])
		var index := counterpart.item_count - 1
		counterpart.set_item_metadata(index, id)
		if id == selected:
			counterpart.select(index)
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for loan: Dictionary in state.get("loans", []):
		if own not in [loan.lender, loan.borrower]:
			continue
		var panel := VBoxContainer.new()
		rows.add_child(panel)
		var terms := tr("%s → %s · %s · %d%% annually") % [names.get(loan.lender, ""), names.get(loan.borrower, ""), MultiplayerScoreboard.money(loan.amount), int(loan.rate)]
		var caption := ApplicationMultiplayer.label(panel, terms)
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if loan.status == "offered":
			var actions := HBoxContainer.new()
			panel.add_child(actions)
			if own != loan.proposer:
				ApplicationMultiplayer.button(actions, tr("Approve loan"), func() -> void: coop.session.request({"kind": "loan_accept", "loan": loan.id}))
			ApplicationMultiplayer.button(actions, tr("Withdraw") if own == loan.proposer else tr("Decline"), func() -> void: coop.session.request({"kind": "loan_cancel", "loan": loan.id}))
		else:
			ApplicationMultiplayer.label(panel, tr("Outstanding: %s · Unpaid interest: %s") % [MultiplayerScoreboard.money(loan.principal), MultiplayerScoreboard.money(loan.arrears)])
			if own == loan.borrower and loan.status == "active":
				ApplicationMultiplayer.button(panel, tr("Repay principal"), func() -> void: coop.session.request({"kind": "loan_repay", "loan": loan.id}))
		panel.add_child(HSeparator.new())
