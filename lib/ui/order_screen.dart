import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../data/models.dart';
import '../state/app_controller.dart';
import 'home_screen.dart' show CategoryFilters, DishTile;
import 'theme.dart';

class OrderScreen extends StatefulWidget {
  final AppController app;
  final DiningTable table;
  const OrderScreen({super.key, required this.app, required this.table});
  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  int _tab = 0;
  String _search = '', _category = 'All';
  bool _guestBusy = false;
  AppController get app => widget.app;
  DiningTable get table => widget.table;
  ServiceOrder? get order => app.snapshot.orderFor(table.id);
  List<OrderLine> get items =>
      app.snapshot.items.where((i) => i.orderId == order?.id).toList();
  @override
  void initState() {
    super.initState();
    if (order != null) _tab = 1;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => app.refresh(reloadMenu: true));
  }

  Future<bool> _action(Future<void> Function() action, String success) async {
    try {
      await action();
      if (mounted) showMessage(context, success);
      return true;
    } catch (e) {
      if (mounted) showMessage(context, e.toString());
      return false;
    }
  }

  Future<void> _add(Dish dish) async {
    StockBatch? batch;
    if (dish.needsBatch) {
      if (dish.batches.length == 1) {
        batch = dish.batches.first;
      } else {
        batch = await showModalBottomSheet<StockBatch>(
            context: context,
            useSafeArea: true,
            builder: (context) => ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                    children: [
                      Text('Choose a batch',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(dish.name,
                          style: const TextStyle(color: Palette.muted)),
                      const SizedBox(height: 16),
                      ...dish.batches.map((b) => Card(
                          child: ListTile(
                              title: Text(b.label),
                              subtitle: Text(
                                  '${b.quantity} available${b.expires == null ? '' : ' • Expires ${b.expires!.toIso8601String().substring(0, 10)}'}'),
                              trailing: Text(money(b.price),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                              onTap: () => Navigator.pop(context, b))))
                    ]));
      }
      if (batch == null || !mounted) return;
    }
    try {
      app.add(table.id, dish, batch: batch);
      HapticFeedback.selectionClick();
    } catch (e) {
      if (mounted) showMessage(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        if (app.user == null) return const SizedBox.shrink();
        final current = order;
        final locked = current?.lockedFor(app.user!) == true;
        final billed = current?.billed == true;
        final uncertain = app.uncertainTables.contains(table.id);
        final canEdit =
            !locked && !billed && !app.offline && !uncertain && !app.busy;
        final canServe = !locked && !app.offline && !uncertain && !app.busy;
        final shown = app.dishes
            .where((d) =>
                (_category == 'All' || d.category == _category) &&
                '${d.name} ${d.description}'
                    .toLowerCase()
                    .contains(_search.toLowerCase()))
            .toList();
        return Scaffold(
          appBar: AppBar(
              titleSpacing: 0,
              title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Table ${table.number.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w800)),
                    Text('${table.section} • ${table.capacity} seats',
                        style:
                            const TextStyle(fontSize: 11, color: Palette.muted))
                  ]),
              actions: [
                IconButton(
                    tooltip: 'Refresh order',
                    onPressed: app.loading
                        ? null
                        : () => app.refresh(reloadMenu: true),
                    icon: const Icon(Icons.refresh_rounded)),
              ]),
          body: SafeArea(
              top: false,
              child: Column(children: [
                if (app.demo)
                  const Notice(
                      icon: Icons.school_outlined,
                      text: 'Practice table • Changes stay on this device',
                      color: Palette.amber,
                      background: Palette.peach),
                if (app.offline)
                  const Notice(
                      icon: Icons.wifi_off,
                      text:
                          'Offline. Reconnect and refresh before sending changes.',
                      color: Palette.red,
                      background: Color(0xFFFFE7E2)),
                if (app.staleDraftTables.contains(table.id))
                  const Notice(
                      icon: Icons.info_outline,
                      text:
                          'The previous order ended. Its unsent draft was cleared; confirm the new table before ordering.',
                      color: Palette.amber,
                      background: Palette.peach),
                if (locked)
                  Notice(
                      icon: Icons.lock_outline,
                      text:
                          '${current!.waiterName ?? 'Another waiter'} is serving this table. You can view the order.',
                      color: Palette.muted,
                      background: Palette.mint),
                if (uncertain)
                  Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                              color: Palette.peach,
                              borderRadius: BorderRadius.circular(14)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Check the last action',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Palette.amber)),
                                const SizedBox(height: 6),
                                const Text(
                                    'It may already have reached the restaurant. Refresh and compare the live order with your draft before continuing.',
                                    style: TextStyle(
                                        fontSize: 11, color: Palette.amber)),
                                Wrap(spacing: 8, children: [
                                  TextButton(
                                      onPressed: () {
                                        setState(() => _tab = 1);
                                        app.refresh(reloadMenu: true);
                                      },
                                      child: const Text('Refresh live order')),
                                  TextButton(
                                      onPressed: app.busy
                                          ? null
                                          : () async {
                                              final yes = await confirm(context,
                                                  title:
                                                      'Have you checked the live order?',
                                                  message:
                                                      'This clears the unsent draft and unlocks this table on your phone. Add only missing items afterwards. If stock or totals look wrong, ask the cashier to reconcile them.',
                                                  action:
                                                      'Checked — clear draft');
                                              if (yes) {
                                                await _action(
                                                    () => app
                                                        .acknowledge(table.id),
                                                    'Draft cleared. Add only items still missing.');
                                              }
                                            },
                                      child: const Text('I’ve checked'))
                                ])
                              ]))),
                Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                            color: const Color(0xFFECEEE7),
                            borderRadius: BorderRadius.circular(13)),
                        child: Row(children: [
                          _segment('Menu', 0, Icons.restaurant_menu),
                          _segment(
                              'Live order (${items.fold(0, (n, i) => n + i.quantity)})',
                              1,
                              Icons.receipt_long_outlined)
                        ]))),
                Expanded(
                    child: RefreshIndicator(
                        onRefresh: () => app.refresh(reloadMenu: true),
                        child: _tab == 0
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(20),
                                children: [
                                    const Text('A good meal starts here.',
                                        style: TextStyle(
                                            fontFamily: 'Lora',
                                            fontSize: 23,
                                            color: Palette.ink)),
                                    const SizedBox(height: 7),
                                    const Text(
                                        'Tap + to add. Review everything before sending.',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Palette.muted)),
                                    const SizedBox(height: 18),
                                    TextField(
                                        onChanged: (v) =>
                                            setState(() => _search = v),
                                        decoration: const InputDecoration(
                                            hintText: 'Find a dish or drink',
                                            prefixIcon:
                                                Icon(Icons.search_rounded),
                                            isDense: true)),
                                    const SizedBox(height: 12),
                                    CategoryFilters(
                                        categories: app.dishes
                                            .map((d) => d.category)
                                            .toSet()
                                            .toList(),
                                        selected: _category,
                                        onSelect: (c) =>
                                            setState(() => _category = c)),
                                    const SizedBox(height: 20),
                                    if (app.loading && app.dishes.isEmpty)
                                      const Center(
                                          child: CircularProgressIndicator()),
                                    ...shown.map((dish) => DishTile(
                                        dish: dish,
                                        add: canEdit ? () => _add(dish) : null,
                                        count: app
                                            .cart(table.id)
                                            .where((l) => l.dish.id == dish.id)
                                            .fold(
                                                0, (n, l) => n + l.quantity))),
                                    if (shown.isEmpty && !app.loading)
                                      const EmptyState(
                                          icon: Icons.search_off,
                                          title: 'No dishes found',
                                          description:
                                              'Try another search or refresh the menu.'),
                                  ])
                            : _liveOrder(
                                current, locked, billed, canEdit, canServe))),
              ])),
          bottomNavigationBar: app.cartCount(table.id) > 0
              ? SafeArea(top: false, child: _bottomCart(canEdit))
              : current != null && !locked && !billed
                  ? SafeArea(
                      top: false,
                      child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                          child: SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                  onPressed:
                                      canEdit && current.ownedBy(app.user!)
                                          ? () => _cashier(current)
                                          : null,
                                  icon: const Icon(Icons.receipt_long_outlined,
                                      size: 20),
                                  label: Text(app.busy
                                      ? 'Please wait…'
                                      : 'Send bill to cashier')))))
                  : null,
        );
      });
  Widget _segment(String label, int tab, IconData icon) => Expanded(
      child: InkWell(
          onTap: () => setState(() => _tab = tab),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 5),
              decoration: BoxDecoration(
                  color: _tab == tab ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10)),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon,
                    size: 17,
                    color: _tab == tab ? Palette.forest : Palette.muted),
                const SizedBox(width: 7),
                Flexible(
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color:
                                _tab == tab ? Palette.forest : Palette.muted)))
              ]))));

  Widget _liveOrder(ServiceOrder? current, bool locked, bool billed,
      bool canEdit, bool canServe) {
    if (current == null) {
      return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 40),
            EmptyState(
                icon: Icons.room_service_outlined,
                title: 'A fresh start for this table',
                description:
                    'Choose dishes from the menu, review your draft, then send the order to begin service.',
                action: FilledButton.icon(
                    onPressed: () => setState(() => _tab = 0),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Explore the menu')))
          ]);
    }
    return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          if (billed)
            Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Palette.peach,
                    borderRadius: BorderRadius.circular(17)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.receipt_long_outlined,
                          color: Palette.amber, size: 28),
                      const SizedBox(height: 12),
                      Text(
                          current.confirmedTotal != null
                              ? 'The bill is ready.'
                              : 'Over to the cashier.',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 7),
                      Text(
                          current.confirmedTotal != null
                              ? 'The cashier has confirmed the total. You can show the bill to your guests.'
                              : 'The cashier is reviewing the bill. This page updates automatically.',
                          style: const TextStyle(
                              fontSize: 12, color: Palette.amber)),
                      const SizedBox(height: 15),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                              onPressed: current.confirmedTotal != null
                                  ? () => showBill(context, app, current, table)
                                  : null,
                              child: Text(current.confirmedTotal != null
                                  ? 'View bill • ${money(current.confirmedTotal!)}'
                                  : 'Waiting for confirmation')))
                    ])),
          if (billed) const SizedBox(height: 22),
          Row(children: [
            const Expanded(
                child: Text('SENT TO RESTAURANT',
                    style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                        color: Palette.muted))),
            StatusTag(billed ? 'With cashier' : 'In service',
                color: billed ? Palette.amber : Palette.green,
                background: billed ? Palette.peach : Palette.mint)
          ]),
          const SizedBox(height: 16),
          ...items.map((line) {
            final direct = line.batchId != null ||
                app.dishes.any((d) => d.id == line.menuItemId && d.inventoried);
            final ready = line.readyToServe || direct;
            final status = line.fullyServed
                ? 'Served'
                : ready
                    ? 'Ready to serve'
                    : line.kitchenStatus == 'preparing'
                        ? 'Preparing'
                        : 'With kitchen';
            return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                        width: 34,
                                        height: 34,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                            color: Palette.mint,
                                            borderRadius:
                                                BorderRadius.circular(9)),
                                        child: Text('${line.quantity}×',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: Palette.green))),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(line.name,
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w800)),
                                          const SizedBox(height: 5),
                                          Text(
                                              money(line.price * line.quantity),
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Palette.muted))
                                        ]))
                                  ]),
                              const SizedBox(height: 14),
                              Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 12,
                                  runSpacing: 6,
                                  children: [
                                    StatusTag(status,
                                        icon: line.fullyServed
                                            ? Icons.check
                                            : ready
                                                ? Icons.room_service_outlined
                                                : Icons.schedule,
                                        color: ready || line.fullyServed
                                            ? Palette.green
                                            : Palette.amber,
                                        background: ready || line.fullyServed
                                            ? Palette.mint
                                            : Palette.peach),
                                    if (line.served > 0)
                                      Text(
                                          '${line.served}/${line.quantity} served',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Palette.muted)),
                                    if (ready &&
                                        !line.fullyServed &&
                                        !locked &&
                                        current.ownedBy(app.user!))
                                      TextButton.icon(
                                          onPressed: canServe
                                              ? () => _action(
                                                  () => app.perform(
                                                      table.id,
                                                      (r, s) => r.serve(
                                                          current, line, s)),
                                                  'Marked as served.')
                                              : null,
                                          icon: const Icon(Icons.check_rounded,
                                              size: 17),
                                          label: const Text('Mark served',
                                              style: TextStyle(fontSize: 11)))
                                  ])
                            ]))));
          }),
          const SizedBox(height: 10),
          Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: Palette.mint, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Expanded(
                    child: Text('Order subtotal',
                        style: TextStyle(fontWeight: FontWeight.w700))),
                Text(money(current.total),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: Palette.forest))
              ])),
          const SizedBox(height: 8),
          const Text(
              'Final charges and discounts are confirmed by the cashier.',
              style: TextStyle(fontSize: 10, color: Palette.muted)),
          const SizedBox(height: 24),
          Card(
              child: ListTile(
                  leading:
                      const Icon(Icons.qr_code_rounded, color: Palette.green),
                  title: Text(
                      current.customerId != null
                          ? 'Guest linked to this order'
                          : 'Link a staying guest',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      current.customerMobile?.isNotEmpty == true
                          ? current.customerMobile!
                          : 'Scan or enter their check-in pass',
                      style: const TextStyle(fontSize: 10)),
                  trailing: _guestBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: canEdit && current.ownedBy(app.user!) && !_guestBusy
                      ? () => _linkGuest(current)
                      : null)),
          if (canEdit)
            Padding(
                padding: const EdgeInsets.only(top: 16),
                child: OutlinedButton.icon(
                    onPressed: () => setState(() => _tab = 0),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add more items'))),
          const SizedBox(height: 18),
          const Text(
              'Need to correct an item already sent? Ask the cashier to adjust it so kitchen work and stock stay consistent.',
              style:
                  TextStyle(fontSize: 11, color: Palette.muted, height: 1.6)),
        ]);
  }

  Widget _bottomCart(bool canEdit) => Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Palette.line))),
      child: FilledButton(
          onPressed: () => _reviewCart(canEdit),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(7)),
                child: Text('${app.cartCount(table.id)}')),
            const SizedBox(width: 12),
            const Expanded(child: Text('Review draft')),
            Text(money(app.cartTotal(table.id)),
                style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_rounded, size: 18)
          ])));
  Future<void> _cashier(ServiceOrder current) async {
    final remaining = items
        .where((line) => !line.fullyServed)
        .fold<int>(0, (total, line) => total + line.quantity - line.served);
    final yes = await confirm(context,
        title: 'Send Table ${table.number} to the cashier?',
        message: remaining > 0
            ? '$remaining portion${remaining == 1 ? '' : 's'} are not marked served yet. You can still mark existing items served after billing. Add all remaining items before continuing.'
            : 'Your guests’ order will be sent for billing. Only the cashier can confirm payment and close the table.',
        action: 'Send bill');
    if (yes) {
      await _action(
          () => app.perform(table.id, (r, s) => r.sendToCashier(current, s)),
          'Bill sent. The cashier will confirm the final total.');
    }
  }

  Future<void> _reviewCart(bool initiallyEditable) async {
    final phone = TextEditingController(text: order?.customerMobile ?? '');
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheet) => AnimatedBuilder(
            animation: app,
            builder: (sheet, _) {
              final canSend = initiallyEditable &&
                  !app.busy &&
                  !app.offline &&
                  !app.uncertainTables.contains(table.id) &&
                  order?.billed != true &&
                  (app.user != null && order?.lockedFor(app.user!) != true);
              return Padding(
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(sheet).bottom),
                  child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(sheet).height * .85),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                        child: Text('One last look.',
                                            style: Theme.of(sheet)
                                                .textTheme
                                                .headlineMedium)),
                                    StatusTag('TABLE ${table.number}')
                                  ]),
                                  const SizedBox(height: 7),
                                  const Text(
                                      'This is a draft. Items haven’t been sent yet.',
                                      style: TextStyle(
                                          color: Palette.muted, fontSize: 12))
                                ])),
                        Flexible(
                            child: ListView(
                                shrinkWrap: true,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 24),
                                children: [
                              ...app.cart(table.id).toList().map((line) =>
                                  Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 15),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(line.dish.name,
                                                style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w800)),
                                            if (line.batch != null)
                                              Text(line.batch!.label,
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Palette.muted)),
                                            Row(children: [
                                              Expanded(
                                                  child: Text(
                                                      money(line.price *
                                                          line.quantity),
                                                      style: const TextStyle(
                                                          fontSize: 12,
                                                          color:
                                                              Palette.muted))),
                                              IconButton(
                                                  tooltip:
                                                      'Remove one ${line.dish.name}',
                                                  onPressed: canSend
                                                      ? () => app.adjust(
                                                          table.id, line, -1)
                                                      : null,
                                                  icon: const Icon(
                                                      Icons
                                                          .remove_circle_outline,
                                                      size: 23)),
                                              Text('${line.quantity}',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800)),
                                              IconButton(
                                                  tooltip:
                                                      'Add one ${line.dish.name}',
                                                  onPressed: canSend
                                                      ? () {
                                                          try {
                                                            app.adjust(table.id,
                                                                line, 1);
                                                          } catch (e) {
                                                            showMessage(sheet,
                                                                e.toString());
                                                          }
                                                        }
                                                      : null,
                                                  icon: const Icon(
                                                      Icons.add_circle_outline,
                                                      size: 23))
                                            ]),
                                            const Divider()
                                          ]))),
                              TextField(
                                  controller: phone,
                                  keyboardType: TextInputType.phone,
                                  decoration: const InputDecoration(
                                      labelText: 'Guest mobile (optional)',
                                      hintText:
                                          'For the restaurant’s customer record',
                                      prefixIcon: Icon(Icons.phone_outlined,
                                          size: 19))),
                              const SizedBox(height: 16),
                              if (app.uncertainTables.contains(table.id))
                                const Padding(
                                    padding: EdgeInsets.only(bottom: 16),
                                    child: Text(
                                        'Check the live order before sending again. Close this draft to review the last action.',
                                        style: TextStyle(
                                            color: Palette.amber,
                                            fontSize: 12))),
                            ])),
                        Padding(
                            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                            child: Column(children: [
                              Row(children: [
                                const Expanded(
                                    child: Text('Draft total',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700))),
                                Text(money(app.cartTotal(table.id)),
                                    style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800))
                              ]),
                              const SizedBox(height: 16),
                              SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                      onPressed: canSend &&
                                              app.cartCount(table.id) > 0
                                          ? () async {
                                              final mobile = phone.text.trim();
                                              if (mobile.isNotEmpty &&
                                                  !RegExp(r'^\+?[\d\s()-]{7,20}$')
                                                      .hasMatch(mobile)) {
                                                showMessage(sheet,
                                                    'Enter a valid phone number or leave it empty.');
                                                return;
                                              }
                                              FocusScope.of(sheet).unfocus();
                                              try {
                                                final freshTable = app
                                                        .snapshot.tables
                                                        .where((t) =>
                                                            t.id == table.id)
                                                        .firstOrNull ??
                                                    table;
                                                await app.perform(
                                                    table.id,
                                                    (r, s) => r.submit(
                                                        freshTable,
                                                        s,
                                                        List.of(
                                                            app.cart(table.id)),
                                                        mobile),
                                                    submitting: true);
                                                if (sheet.mounted) {
                                                  Navigator.pop(sheet);
                                                }
                                                if (mounted) {
                                                  setState(() => _tab = 1);
                                                  HapticFeedback.mediumImpact();
                                                  showMessage(context,
                                                      'Order sent. You’re all set.');
                                                }
                                              } catch (e) {
                                                if (sheet.mounted) {
                                                  showMessage(
                                                      sheet, e.toString());
                                                }
                                              }
                                            }
                                          : null,
                                      icon: app.busy
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white))
                                          : const Icon(Icons.send_rounded,
                                              size: 18),
                                      label: Text(app.busy
                                          ? 'Sending…'
                                          : 'Send order to restaurant'))),
                              const SizedBox(height: 8),
                              const Text(
                                  'Check the table and quantities with your guests.',
                                  style: TextStyle(
                                      fontSize: 10, color: Palette.muted))
                            ]))
                      ])));
            }));
    await Future<void>.delayed(const Duration(milliseconds: 350));
    phone.dispose();
  }

  Future<void> _linkGuest(ServiceOrder current) async {
    final input = TextEditingController();
    final code = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: const Text('Link a staying guest'),
                content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                          'Scan the guest’s check-in QR pass, or enter its code.'),
                      const SizedBox(height: 18),
                      TextField(
                          controller: input,
                          decoration: const InputDecoration(
                              labelText: 'Guest pass code')),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                          onPressed: () async {
                            final scanned = await Navigator.push<String>(
                                dialog,
                                MaterialPageRoute(
                                    builder: (_) => const GuestScanner()));
                            if (scanned != null && dialog.mounted) {
                              Navigator.pop(dialog, scanned);
                            }
                          },
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Scan QR pass'))
                    ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () {
                        if (input.text.trim().isNotEmpty) {
                          Navigator.pop(dialog, input.text.trim());
                        }
                      },
                      child: const Text('Find guest'))
                ]));
    await Future<void>.delayed(const Duration(milliseconds: 350));
    input.dispose();
    if (code == null || !mounted) return;
    setState(() => _guestBusy = true);
    try {
      final guest = await app.repository!.findGuest(code);
      if (!mounted) return;
      final yes = await confirm(context,
          title: 'Link ${guest['name']}?',
          message:
              '${guest['current_room'] ?? 'Checked-in guest'}\nThis guest will be attached to Table ${table.number}.',
          action: 'Link guest');
      if (yes) {
        await _action(
            () => app.perform(
                table.id, (r, s) => r.attachGuest(current, guest, s)),
            'Guest linked to this order.');
      }
    } catch (e) {
      if (mounted) showMessage(context, e.toString());
    } finally {
      if (mounted) setState(() => _guestBusy = false);
    }
  }
}

class Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color, background;
  const Notice(
      {super.key,
      required this.icon,
      required this.text,
      required this.color,
      required this.background});
  @override
  Widget build(BuildContext context) => Container(
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text, style: TextStyle(fontSize: 11, color: color)))
      ]));
}

Future<void> showBill(BuildContext context, AppController app,
        ServiceOrder initialOrder, DiningTable table) =>
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => AnimatedBuilder(
            animation: app,
            builder: (context, _) {
              final order = app.snapshot.orders
                      .where((candidate) => candidate.id == initialOrder.id)
                      .firstOrNull ??
                  initialOrder;
              final items = app.snapshot.items
                  .where((item) => item.orderId == order.id)
                  .toList();
              final breakdown = order.breakdown;
              Widget row(String label, double value, {bool total = false}) =>
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Expanded(
                            child: Text(label,
                                style: TextStyle(
                                    fontWeight: total
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    fontSize: total ? 18 : 12))),
                        Text(money(value),
                            style: TextStyle(
                                fontWeight:
                                    total ? FontWeight.w800 : FontWeight.w600,
                                fontSize: total ? 18 : 12))
                      ]));
              return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(26, 0, 26, 30),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: BrandMark(size: 50)),
                        const SizedBox(height: 15),
                        const Text('Oruthota Chalets',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: 'Lora', fontSize: 25)),
                        const SizedBox(height: 6),
                        Text(
                            'TABLE ${table.number.toString().padLeft(2, '0')} • GUEST BILL',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 10,
                                letterSpacing: 2,
                                color: Palette.muted)),
                        if (order.billNumber != null)
                          Text(order.billNumber!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 11, color: Palette.muted)),
                        const SizedBox(height: 22),
                        Center(
                            child: StatusTag(
                                order.status == 'closed'
                                    ? 'Settled with cashier'
                                    : 'Total confirmed by cashier',
                                icon: Icons.check_circle_outline)),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 14),
                        ...items.map((i) => row(
                            '${i.quantity} × ${i.name}', i.quantity * i.price)),
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 12),
                        row('Subtotal',
                            number(breakdown?['subtotal'] ?? order.total)),
                        if (breakdown != null) ...[
                          if (number(breakdown['discount_total']) != 0)
                            row('Discounts',
                                -number(breakdown['discount_total'])),
                          ...((breakdown['service_charge_lines'] as List?) ??
                                  [])
                              .map((c) =>
                                  row('${c['name']}', number(c['amount']))),
                          ...((breakdown['other_charge_lines'] as List?) ?? [])
                              .map((c) =>
                                  row('${c['name']}', number(c['amount']))),
                          if (number(breakdown['vat_amount']) != 0)
                            row('VAT (${number(breakdown['vat_rate'])}%)',
                                number(breakdown['vat_amount'])),
                        ] else if (order.confirmedTotal != null &&
                            order.confirmedTotal != order.total)
                          row('Cashier adjustments',
                              order.confirmedTotal! - order.total),
                        const SizedBox(height: 10),
                        const Divider(),
                        const SizedBox(height: 10),
                        row('Total', order.confirmedTotal ?? order.total,
                            total: true),
                        const SizedBox(height: 18),
                        Text(
                            order.status == 'closed'
                                ? 'This order was settled by the cashier.'
                                : 'This is a bill preview, not a payment receipt.\nPlease settle payment with the cashier.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Palette.muted,
                                fontSize: 11,
                                height: 1.7)),
                        const SizedBox(height: 26),
                        FilledButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('Back to table'))
                      ]));
            }));

class GuestScanner extends StatefulWidget {
  const GuestScanner({super.key});
  @override
  State<GuestScanner> createState() => _GuestScannerState();
}

class _GuestScannerState extends State<GuestScanner> {
  final _scanner =
      MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Palette.forest,
      appBar: AppBar(title: const Text('Scan guest pass')),
      body: Stack(children: [
        MobileScanner(
            controller: _scanner,
            onDetect: (capture) {
              final code = capture.barcodes.firstOrNull?.rawValue;
              if (!_done && code != null) {
                _done = true;
                Navigator.pop(context, code);
              }
            },
            errorBuilder: (context, error) => Center(
                child: Card(
                    margin: const EdgeInsets.all(24),
                    child: EmptyState(
                        icon: Icons.no_photography_outlined,
                        title: 'Camera unavailable',
                        description:
                            'Allow camera access in Android settings, or go back and enter the pass code manually.',
                        action: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Enter code instead')))))),
        Center(
            child: IgnorePointer(
                child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                        border: Border.all(
                            color: const Color(0xFFD5DFC8), width: 3),
                        borderRadius: BorderRadius.circular(22))))),
        Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: Palette.forest.withValues(alpha: .85),
                    borderRadius: BorderRadius.circular(16)),
                child: const Text('Place the guest’s QR code inside the frame.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 13))))
      ]));
}
