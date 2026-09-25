import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../data/models.dart';
import '../state/app_controller.dart';
import 'theme.dart';
import 'order_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppController controller;
  const HomeScreen({super.key, required this.controller});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  Set<String> _knownReady = {};

  Set<String> _readyIds() {
    final app = widget.controller;
    final ownOrderIds = app.snapshot.orders
        .where((order) => order.active && order.ownedBy(app.user!))
        .map((order) => order.id)
        .toSet();
    return app.snapshot.items
        .where(
            (item) => ownOrderIds.contains(item.orderId) && item.readyToServe)
        .map((item) => item.id)
        .toSet();
  }

  void _listenForReadyItems() {
    if (!mounted || widget.controller.user == null) return;
    final ready = _readyIds();
    final added = ready.difference(_knownReady);
    _knownReady = ready;
    if (added.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showMessage(context,
          '${added.length} new item${added.length == 1 ? ' is' : 's are'} ready to serve.');
    });
  }

  @override
  void initState() {
    super.initState();
    _knownReady = _readyIds();
    widget.controller.addListener(_listenForReadyItems);
    if (widget.controller.preferences?.getBool('guide_seen') != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showGuide(context);
      });
      widget.controller.preferences?.setBool('guide_seen', true);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_listenForReadyItems);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.controller;
    return Scaffold(
      body: SafeArea(
          child: Column(children: [
        if (app.demo)
          Container(
              width: double.infinity,
              color: Palette.peach,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
              child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.school_outlined, size: 13, color: Palette.amber),
                    SizedBox(width: 7),
                    Text('PRACTICE SHIFT  ·  No live data',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .5,
                            color: Palette.amber))
                  ])),
        if (app.offline)
          Container(
              color: const Color(0xFFFFE7E2),
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(children: [
                const Icon(Icons.wifi_off_rounded,
                    size: 18, color: Palette.red),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                        app.lastSync == null
                            ? 'Could not load the restaurant.'
                            : 'Connection lost. Showing the last update.',
                        style:
                            const TextStyle(fontSize: 11, color: Palette.red))),
                TextButton(
                    onPressed: () => app.refresh(), child: const Text('Retry'))
              ])),
        Expanded(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 850),
                    child: IndexedStack(index: _tab, children: [
                      FloorPage(
                          app: app, openOrders: () => setState(() => _tab = 1)),
                      OrdersPage(app: app),
                      BrowseMenuPage(
                          app: app,
                          chooseTable: () => setState(() => _tab = 0)),
                      TeamPage(app: app),
                    ])))),
      ])),
      bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Palette.line))),
          child: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              height: 72,
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.grid_view_outlined),
                    selectedIcon: Icon(Icons.grid_view_rounded),
                    label: 'Tables'),
                NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    selectedIcon: Icon(Icons.receipt_long),
                    label: 'My orders'),
                NavigationDestination(
                    icon: Icon(Icons.restaurant_menu_outlined), label: 'Menu'),
                NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: 'You'),
              ])),
    );
  }
}

class FloorPage extends StatefulWidget {
  final AppController app;
  final VoidCallback openOrders;
  const FloorPage({super.key, required this.app, required this.openOrders});
  @override
  State<FloorPage> createState() => _FloorPageState();
}

class _FloorPageState extends State<FloorPage> {
  String _query = '', _section = 'All areas', _filter = 'All tables';
  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final staff = app.user!;
    final own =
        app.snapshot.orders.where((o) => o.active && o.ownedBy(staff)).toList();
    final ready = app.snapshot.items
        .where((i) =>
            i.readyToServe && own.any((o) => o.id == i.orderId && !o.billed))
        .length;
    final free = app.snapshot.tables
        .where((t) =>
            app.snapshot.orderFor(t.id) == null && t.status == 'available')
        .length;
    final sections = [
      'All areas',
      ...app.snapshot.tables.map((t) => t.section).toSet()
    ];
    final tables = app.snapshot.tables.where((t) {
      final order = app.snapshot.orderFor(t.id);
      if (_section != 'All areas' && t.section != _section) return false;
      if (_filter == 'My tables' && order?.ownedBy(staff) != true) return false;
      if (_filter == 'Available' &&
          (order != null || t.status != 'available')) {
        return false;
      }
      return '${t.number} ${t.section} ${order?.waiterName ?? ''}'
          .toLowerCase()
          .contains(_query.toLowerCase());
    }).toList();
    return RefreshIndicator(
        onRefresh: () => app.refresh(reloadMenu: true),
        color: Palette.forest,
        child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 0),
                  sliver: SliverToBoxAdapter(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          const BrandMark(size: 34),
                          const SizedBox(width: 10),
                          const Expanded(
                              child: Text('ORUTHOTA / SERVICE',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5))),
                          IconButton(
                              tooltip: 'Quick guide',
                              onPressed: () => showGuide(context),
                              icon: const Icon(Icons.help_outline_rounded,
                                  size: 22)),
                          IconButton(
                              tooltip: 'Refresh tables',
                              onPressed: app.loading
                                  ? null
                                  : () => app.refresh(reloadMenu: true),
                              icon: app.loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.refresh_rounded, size: 23))
                        ]),
                        const SizedBox(height: 14),
                        Text('Hello, ${staff.firstName}.',
                            style: Theme.of(context).textTheme.headlineLarge),
                        const SizedBox(height: 6),
                        Row(children: [
                          Expanded(
                              child: Text(
                                  'Let’s make every table feel welcome.',
                                  style: TextStyle(
                                      color: Palette.muted,
                                      fontSize:
                                          MediaQuery.sizeOf(context).width < 370
                                              ? 11
                                              : 12))),
                          Text(DateFormat('EEE, d MMM').format(DateTime.now()),
                              style: const TextStyle(
                                  fontSize: 10, color: Palette.muted))
                        ]),
                        const SizedBox(height: 18),
                        InkWell(
                            onTap: widget.openOrders,
                            borderRadius: BorderRadius.circular(19),
                            child: Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                    color: Palette.forest,
                                    borderRadius: BorderRadius.circular(19)),
                                child: Row(children: [
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        const Text('YOUR FLOOR, AT A GLANCE',
                                            style: TextStyle(
                                                color: Color(0xFFBCCEBB),
                                                fontSize: 9,
                                                letterSpacing: 1.6,
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 16),
                                        Row(children: [
                                          _HeroStat(
                                              '${own.length}', 'My tables'),
                                          const SizedBox(width: 24),
                                          _HeroStat('$ready', 'Ready to serve'),
                                          const SizedBox(width: 24),
                                          _HeroStat('$free', 'Available')
                                        ])
                                      ])),
                                  const Icon(Icons.arrow_outward_rounded,
                                      size: 22, color: Color(0xFFCCDDBE))
                                ]))),
                        const SizedBox(height: 18),
                        SectionTitle('The restaurant',
                            trailing: Text(
                                '${app.snapshot.tables.length} tables',
                                style: const TextStyle(
                                    fontSize: 11, color: Palette.muted))),
                        const SizedBox(height: 10),
                        TextField(
                            onChanged: (v) => setState(() => _query = v),
                            decoration: const InputDecoration(
                                hintText: 'Find a table or team member',
                                prefixIcon:
                                    Icon(Icons.search_rounded, size: 21),
                                isDense: true)),
                        const SizedBox(height: 14),
                        SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                                children: [
                              'All tables',
                              'My tables',
                              'Available'
                            ]
                                    .map((s) => Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child: ChoiceChip(
                                            label: Text(s,
                                                style: const TextStyle(
                                                    fontSize: 11)),
                                            selected: _filter == s,
                                            showCheckmark: false,
                                            onSelected: (_) =>
                                                setState(() => _filter = s),
                                            selectedColor: Palette.mint,
                                            backgroundColor: Colors.white,
                                            side: BorderSide(
                                                color: _filter == s
                                                    ? Palette.green
                                                    : Palette.line),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(9)))))
                                    .toList())),
                        const SizedBox(height: 8),
                        Row(children: [
                          const Icon(Icons.location_on_outlined,
                              size: 15, color: Palette.muted),
                          const SizedBox(width: 6),
                          Expanded(
                              child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                      isExpanded: true,
                                      value: sections.contains(_section)
                                          ? _section
                                          : 'All areas',
                                      items: sections
                                          .map((s) => DropdownMenuItem(
                                              value: s,
                                              child: Text(s,
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600))))
                                          .toList(),
                                      onChanged: (v) =>
                                          setState(() => _section = v!)))),
                          const SizedBox(width: 16),
                          Text(
                              app.lastSync == null
                                  ? 'Not synced'
                                  : 'Updated ${DateFormat('HH:mm').format(app.lastSync!)}',
                              style: const TextStyle(
                                  fontSize: 10, color: Palette.muted))
                        ]),
                      ]))),
              if (app.loading && app.snapshot.tables.isEmpty)
                const SliverToBoxAdapter(
                    child: Padding(
                        padding: EdgeInsets.all(50),
                        child: Center(child: CircularProgressIndicator())))
              else if (tables.isEmpty)
                SliverToBoxAdapter(
                    child: EmptyState(
                        icon: Icons.table_restaurant_outlined,
                        title:
                            app.offline ? 'Let’s reconnect' : 'No tables here',
                        description: app.offline
                            ? app.error ?? 'Check the restaurant connection.'
                            : 'Try another area or clear your search.',
                        action: app.offline
                            ? OutlinedButton(
                                onPressed: () => app.refresh(),
                                child: const Text('Try again'))
                            : null))
              else
                SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
                    sliver: SliverLayoutBuilder(
                        builder: (context, constraints) => SliverGrid(
                            delegate: SliverChildBuilderDelegate(
                                (context, i) => TableCard(
                                    table: tables[i],
                                    order: app.snapshot.orderFor(tables[i].id),
                                    app: app),
                                childCount: tables.length),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount:
                                    constraints.crossAxisExtent > 600 ? 3 : 2,
                                mainAxisExtent:
                                    MediaQuery.textScalerOf(context).scale(1) >
                                            1.2
                                        ? 230
                                        : 189,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12)))),
            ]));
  }
}

class _HeroStat extends StatelessWidget {
  final String count, label;
  const _HeroStat(this.count, this.label);
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(count,
            style: const TextStyle(
                fontFamily: 'Lora', fontSize: 29, color: Colors.white)),
        const SizedBox(height: 5),
        Text(label,
            style: const TextStyle(fontSize: 9, color: Color(0xFFCCD9C9)))
      ]);
}

class TableCard extends StatelessWidget {
  final DiningTable table;
  final ServiceOrder? order;
  final AppController app;
  const TableCard(
      {super.key, required this.table, required this.order, required this.app});
  @override
  Widget build(BuildContext context) {
    final mine = order?.ownedBy(app.user!) == true;
    final billed = order?.billed == true;
    final reserved = order == null && table.status == 'reserved';
    final label = billed
        ? 'With cashier'
        : order != null
            ? mine
                ? 'My table'
                : order!.waiterId == null
                    ? 'Unassigned'
                    : 'In service'
            : reserved
                ? 'Reserved'
                : table.status == 'occupied'
                    ? 'Occupied'
                    : 'Available';
    final color = billed
        ? Palette.amber
        : reserved
            ? const Color(0xFF7A6397)
            : Palette.green;
    final bg = billed
        ? Palette.peach
        : reserved
            ? const Color(0xFFF0EBF6)
            : Palette.mint;
    return Semantics(
        button: true,
        label: 'Table ${table.number}, $label, ${table.capacity} seats',
        child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
                side: BorderSide(
                    color: mine ? const Color(0xFFAFC6B2) : Palette.line)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
                onTap: () => openTable(context, app, table),
                child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: StatusTag(label,
                                    color: color, background: bg)),
                            const SizedBox(width: 3),
                            if (order?.lockedFor(app.user!) == true)
                              const Icon(Icons.lock_outline,
                                  size: 14, color: Palette.muted)
                          ]),
                          const SizedBox(height: 14),
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(table.number.toString().padLeft(2, '0'),
                                    style: const TextStyle(
                                        fontFamily: 'Lora',
                                        fontSize: 35,
                                        height: 1.1,
                                        color: Palette.ink)),
                                const Spacer(),
                                Icon(Icons.table_restaurant_outlined,
                                    size: 28,
                                    color: color.withValues(alpha: .5))
                              ]),
                          const SizedBox(height: 7),
                          Text(table.section,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10, color: Palette.muted)),
                          const Spacer(),
                          const Divider(),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(
                                child: order == null
                                    ? Row(children: [
                                        const Icon(Icons.people_outline,
                                            size: 14, color: Palette.muted),
                                        const SizedBox(width: 4),
                                        Text('${table.capacity} seats',
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: Palette.muted))
                                      ])
                                    : Text(
                                        money(order!.confirmedTotal ??
                                            order!.total),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800))),
                            Icon(
                                app.cartCount(table.id) > 0
                                    ? Icons.shopping_bag_outlined
                                    : Icons.arrow_forward_rounded,
                                size: 17,
                                color: Palette.green)
                          ]),
                        ])))));
  }
}

void openTable(BuildContext context, AppController app, DiningTable table) =>
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => OrderScreen(app: app, table: table)));

class OrdersPage extends StatelessWidget {
  final AppController app;
  const OrdersPage({super.key, required this.app});
  @override
  Widget build(BuildContext context) {
    final orders = app.snapshot.orders
        .where((o) => o.active && o.ownedBy(app.user!))
        .toList();
    final recent = app.snapshot.orders
        .where((o) => o.status == 'closed' && o.ownedBy(app.user!))
        .toList();
    final ready = app.snapshot.items
        .where((i) =>
            i.readyToServe && orders.any((o) => o.id == i.orderId && !o.billed))
        .toList();
    return RefreshIndicator(
        onRefresh: () => app.refresh(),
        child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(22),
            children: [
              const SizedBox(height: 14),
              const Text('YOUR SERVICE',
                  style: TextStyle(
                      letterSpacing: 2,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Palette.muted)),
              const SizedBox(height: 10),
              Text('A smooth service.',
                  style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 8),
              const Text('Stay close to every order, from kitchen to table.',
                  style: TextStyle(color: Palette.muted, fontSize: 12)),
              const SizedBox(height: 28),
              if (ready.isNotEmpty) ...[
                SectionTitle('Ready to serve',
                    trailing: StatusTag('${ready.length} ready',
                        icon: Icons.room_service_outlined)),
                const SizedBox(height: 12),
                ...ready.map((line) {
                  final order = orders.firstWhere((o) => o.id == line.orderId);
                  final table = app.snapshot.tables
                      .firstWhere((t) => t.id == order.tableId);
                  return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                          child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              leading: Container(
                                  width: 44,
                                  height: 44,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                      color: Palette.mint,
                                      borderRadius: BorderRadius.circular(12)),
                                  child: Text('${table.number}'.padLeft(2, '0'),
                                      style: const TextStyle(
                                          fontFamily: 'Lora',
                                          fontSize: 22,
                                          color: Palette.forest))),
                              title: Text(line.name,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                  '${line.readyQuantity - line.served} ready • Table ${table.number}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Palette.green)),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => openTable(context, app, table))));
                }),
                const SizedBox(height: 24)
              ],
              SectionTitle('My active tables',
                  trailing: Text('${orders.length} orders',
                      style:
                          const TextStyle(fontSize: 11, color: Palette.muted))),
              const SizedBox(height: 12),
              if (orders.isEmpty)
                const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Your next table awaits',
                    description:
                        'Open an available table and send your first order. It will appear here.'),
              ...orders.map((order) {
                final table = app.snapshot.tables
                    .where((t) => t.id == order.tableId)
                    .firstOrNull;
                if (table == null) return const SizedBox.shrink();
                return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                        child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => openTable(context, app, table),
                            child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Expanded(
                                            child: Text(
                                                'Table ${table.number.toString().padLeft(2, '0')}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge)),
                                        StatusTag(
                                            order.billed
                                                ? 'With cashier'
                                                : 'In service',
                                            color: order.billed
                                                ? Palette.amber
                                                : Palette.green,
                                            background: order.billed
                                                ? Palette.peach
                                                : Palette.mint)
                                      ]),
                                      const SizedBox(height: 6),
                                      Text(table.section,
                                          style: const TextStyle(
                                              color: Palette.muted,
                                              fontSize: 11)),
                                      const SizedBox(height: 18),
                                      Row(children: [
                                        Expanded(
                                            child: Text(
                                                '${app.snapshot.items.where((i) => i.orderId == order.id).fold(0, (n, i) => n + i.quantity)} items',
                                                style: const TextStyle(
                                                    color: Palette.muted,
                                                    fontSize: 12))),
                                        Text(
                                            money(order.confirmedTotal ??
                                                order.total),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800)),
                                        const SizedBox(width: 10),
                                        const Icon(Icons.arrow_forward_rounded,
                                            size: 16)
                                      ])
                                    ])))));
              }),
              if (recent.isNotEmpty) ...[
                const SizedBox(height: 22),
                SectionTitle('Recent bills',
                    trailing: Text('${recent.length} settled',
                        style: const TextStyle(
                            fontSize: 11, color: Palette.muted))),
                const SizedBox(height: 10),
                ...recent.map((order) {
                  final table = app.snapshot.tables
                      .where((t) => t.id == order.tableId)
                      .firstOrNull;
                  if (table == null) return const SizedBox.shrink();
                  return Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Card(
                          child: ListTile(
                        leading: const Icon(Icons.receipt_long_outlined,
                            color: Palette.green),
                        title: Text(
                            'Table ${table.number.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        subtitle: Text(order.billNumber ?? 'Settled order',
                            style: const TextStyle(fontSize: 10)),
                        trailing: Text(
                            money(order.confirmedTotal ?? order.total),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                        onTap: () => showBill(context, app, order, table),
                      )));
                }),
              ],
            ]));
  }
}

class BrowseMenuPage extends StatefulWidget {
  final AppController app;
  final VoidCallback chooseTable;
  const BrowseMenuPage(
      {super.key, required this.app, required this.chooseTable});
  @override
  State<BrowseMenuPage> createState() => _BrowseMenuPageState();
}

class _BrowseMenuPageState extends State<BrowseMenuPage> {
  String _query = '', _category = 'All';
  @override
  Widget build(BuildContext context) {
    final dishes = widget.app.dishes
        .where((d) =>
            (_category == 'All' || d.category == _category) &&
            '${d.name} ${d.description}'
                .toLowerCase()
                .contains(_query.toLowerCase()))
        .toList();
    return RefreshIndicator(
        onRefresh: () => widget.app.refresh(reloadMenu: true),
        child: ListView(padding: const EdgeInsets.all(22), children: [
          const SizedBox(height: 14),
          const Text('MADE WITH CARE',
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w800,
                  color: Palette.muted)),
          const SizedBox(height: 10),
          Text('On the menu.',
              style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 8),
          const Text('Get to know what you’re serving today.',
              style: TextStyle(fontSize: 12, color: Palette.muted)),
          const SizedBox(height: 24),
          TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search dishes and drinks')),
          const SizedBox(height: 12),
          CategoryFilters(
              categories:
                  widget.app.dishes.map((d) => d.category).toSet().toList(),
              selected: _category,
              onSelect: (c) => setState(() => _category = c)),
          const SizedBox(height: 18),
          ...dishes.map((d) => DishTile(dish: d)),
          if (dishes.isEmpty)
            const EmptyState(
                icon: Icons.restaurant_menu,
                title: 'Nothing on this page yet',
                description: 'Try a different category, or refresh the menu.'),
          const SizedBox(height: 20),
          FilledButton.icon(
              onPressed: widget.chooseTable,
              icon: const Icon(Icons.table_restaurant_outlined),
              label: const Text('Choose a table to take an order')),
          const SizedBox(height: 12)
        ]));
  }
}

class CategoryFilters extends StatelessWidget {
  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelect;
  const CategoryFilters(
      {super.key,
      required this.categories,
      required this.selected,
      required this.onSelect});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
          children: ['All', ...categories]
              .map((c) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                      label: Text(c, style: const TextStyle(fontSize: 11)),
                      selected: selected == c,
                      onSelected: (_) => onSelect(c),
                      showCheckmark: false,
                      selectedColor: Palette.mint,
                      backgroundColor: Colors.white,
                      side: BorderSide(
                          color: selected == c ? Palette.green : Palette.line),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)))))
              .toList()));
}

class DishTile extends StatelessWidget {
  final Dish dish;
  final VoidCallback? add;
  final int count;
  const DishTile({super.key, required this.dish, this.add, this.count = 0});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                  color: count > 0 ? const Color(0xFFAFC6B2) : Palette.line),
              borderRadius: BorderRadius.circular(16)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: 52,
                height: 58,
                decoration: BoxDecoration(
                    color: dish.category.toLowerCase().contains('drink')
                        ? const Color(0xFFF0EADB)
                        : Palette.mint,
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(dishIcon(dish.category),
                    size: 27, color: Palette.green)),
            const SizedBox(width: 13),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(dish.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 4),
                  if (dish.description.isNotEmpty)
                    Text(dish.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Palette.muted, height: 1.5)),
                  const SizedBox(height: 9),
                  Text(dish.displayPrice,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Palette.forest)),
                  if (dish.inventoried)
                    Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                            dish.availableToOrder
                                ? '${dish.available} available'
                                : 'Currently unavailable',
                            style: TextStyle(
                                fontSize: 11,
                                color: dish.availableToOrder
                                    ? Palette.muted
                                    : Palette.red)))
                ])),
            if (add != null) ...[
              const SizedBox(width: 5),
              IconButton.filledTonal(
                  tooltip: 'Add ${dish.name}',
                  onPressed: dish.availableToOrder ? add : null,
                  style: IconButton.styleFrom(
                      backgroundColor:
                          count > 0 ? Palette.forest : Palette.mint,
                      foregroundColor:
                          count > 0 ? Colors.white : Palette.forest,
                      minimumSize: const Size(48, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  icon: count > 0
                      ? Text('$count',
                          style: const TextStyle(fontWeight: FontWeight.w800))
                      : const Icon(Icons.add, size: 21))
            ]
          ])));
}

class TeamPage extends StatelessWidget {
  final AppController app;
  const TeamPage({super.key, required this.app});
  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 22),
        Text('Your corner.', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 22),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  CircleAvatar(
                      radius: 28,
                      backgroundColor: Palette.mint,
                      child: Text(app.user!.name.substring(0, 1),
                          style: const TextStyle(
                              fontFamily: 'Lora',
                              fontSize: 27,
                              color: Palette.forest))),
                  const SizedBox(width: 16),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(app.user!.name,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 5),
                        Text(
                            app.demo
                                ? 'Practice team member'
                                : 'Restaurant team • ${app.user!.role}',
                            style: const TextStyle(
                                color: Palette.muted, fontSize: 11))
                      ]))
                ]))),
        const SizedBox(height: 26),
        const SectionTitle('A helping hand'),
        const SizedBox(height: 12),
        Card(
            child: Column(children: [
          ListTile(
              leading: const Icon(Icons.explore_outlined),
              title: const Text('Quick start guide',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              subtitle: const Text('Your first order, in three steps',
                  style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showGuide(context)),
          const Divider(indent: 56),
          ListTile(
              leading: const Icon(Icons.wifi_rounded),
              title: const Text('Connection',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              subtitle: Text(
                  app.demo
                      ? 'Practice mode • works offline'
                      : app.config.server,
                  style: const TextStyle(fontSize: 11)),
              trailing: Icon(
                  app.offline
                      ? Icons.warning_amber
                      : Icons.check_circle_outline,
                  color: Palette.green)),
          const Divider(indent: 56),
          ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About Oruthota Service',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              subtitle: const Text('Version 1.0.1 • Made for your team',
                  style: TextStyle(fontSize: 11)),
              onTap: () => showAboutDialog(
                      context: context,
                      applicationName: 'Oruthota Service',
                      applicationVersion: '1.0.1',
                      applicationIcon: const BrandMark(),
                      children: [
                        const Text(
                            'A service companion for Oruthota Chalets. Tables, orders, kitchen progress and cashier handoff using the existing restaurant system.')
                      ]))
        ])),
        const SizedBox(height: 26),
        Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Palette.mint, borderRadius: BorderRadius.circular(18)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.favorite_outline, color: Palette.green),
              const SizedBox(height: 12),
              Text('Good service starts with you.',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                  'Check your table, review the order with your guests, and keep an eye on the kitchen.',
                  style: TextStyle(
                      fontSize: 12, color: Palette.green, height: 1.7))
            ])),
        const SizedBox(height: 28),
        OutlinedButton.icon(
            onPressed: app.busy
                ? null
                : () async {
                    final yes = await confirm(context,
                        title: app.demo
                            ? 'Leave practice shift?'
                            : 'End your session?',
                        message:
                            'Saved orders stay with the restaurant. Unsent drafts on this phone will be cleared.',
                        action: 'Sign out');
                    if (yes) await app.signOut();
                  },
            icon: const Icon(Icons.logout, size: 18),
            label: Text(app.demo ? 'Leave practice shift' : 'Sign out')),
        const SizedBox(height: 20)
      ]);
}

Future<void> showGuide(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(26, 0, 26, 30),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const StatusTag('WELCOME TO THE TEAM',
                  icon: Icons.waving_hand_outlined),
              const SizedBox(height: 18),
              Text('Your first order,\nmade simple.',
                  style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 25),
              ...[
                (
                  Icons.table_restaurant_outlined,
                  '01',
                  'Choose your table',
                  'Tap the table your guests are seated at. Tables assigned to another waiter are view-only.'
                ),
                (
                  Icons.restaurant_menu_rounded,
                  '02',
                  'Build & review the order',
                  'Add dishes, check quantities in your draft, then send. Only sent items reach the restaurant.'
                ),
                (
                  Icons.room_service_outlined,
                  '03',
                  'Serve, then send the bill',
                  'Watch for ready dishes and mark them served. When your guests are finished, send the bill to the cashier.'
                )
              ].map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                                color: Palette.mint,
                                borderRadius: BorderRadius.circular(14)),
                            child: Icon(s.$1, color: Palette.green)),
                        const SizedBox(width: 16),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('${s.$2}   ${s.$3}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13)),
                              const SizedBox(height: 6),
                              Text(s.$4,
                                  style: const TextStyle(
                                      color: Palette.muted,
                                      fontSize: 12,
                                      height: 1.6))
                            ]))
                      ]))),
              const Text(
                  'Unsent drafts are saved on this device while you stay signed in. Review them before signing out.',
                  style: TextStyle(fontSize: 11, color: Palette.muted)),
              const SizedBox(height: 24),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Got it. Let’s get started.')))
            ])));
