// 注入到被调试应用里的代理：fdd.mjs 读取本文件、去掉整行注释并压成一行后，
// 在 package:flutter/src/widgets/binding.dart 的作用域里 evaluate 一次。
// 约束：字符串字面量不能跨行，不能写行尾注释；该作用域看不到的类型用 dynamic 访问。
// 每个能力注册成 ext.fd.<版本>.<名字> 服务扩展，状态保存在闭包里，热重载后仍在，热重启后由 fdd 重新注入。
(() {
  const ver = '__FD_VERSION__';
  // 合成指针的 device 号，与真实设备分开，保证 hover 进出状态连续
  const touchDev = 32760;
  const mouseDev = 32761;
  final wb = WidgetsBinding.instance;
  final sched = SchedulerBinding.instance;
  final gb = GestureBinding.instance;
  int now() => DateTime.now().millisecondsSinceEpoch;
  int ptr = 1000000;
  int pumpUntil = 0;
  Timer? pumpTimer;
  final refs = <int, List<Object>>{};
  final semHandle = (wb as dynamic).ensureSemantics();

  String js(String s) {
    final b = StringBuffer('"');
    for (final c in s.codeUnits) {
      if (c == 34) { b.write('\\"'); }
      else if (c == 92) { b.write('\\\\'); }
      else if (c < 32) { b.write('\\u' + c.toRadixString(16).padLeft(4, '0')); }
      else { b.writeCharCode(c); }
    }
    b.write('"');
    return b.toString();
  }

  // 应用不可见时框架会停止排帧（framesEnabled=false）；代理操作期间强制出帧，保证后台也能刷新界面、推进动画
  void pump(int ms) {
    final until = now() + ms;
    if (until > pumpUntil) pumpUntil = until;
    pumpTimer ??= Timer.periodic(const Duration(milliseconds: 16), (t) {
      if (now() > pumpUntil) { t.cancel(); pumpTimer = null; return; }
      if (!sched.framesEnabled) sched.scheduleForcedFrame();
    });
  }

  Future<void> settle(int ms) async {
    pump(ms + 1500);
    if (ms > 0) await Future<void>.delayed(Duration(milliseconds: ms));
    if (sched.hasScheduledFrame) await sched.endOfFrame.timeout(const Duration(seconds: 2), onTimeout: () {});
  }

  List<double> mul(List<double> a, List<double> b) {
    final r = List<double>.filled(16, 0);
    for (var c = 0; c < 4; c++) {
      for (var w = 0; w < 4; w++) {
        var s = 0.0;
        for (var k = 0; k < 4; k++) { s += a[k * 4 + w] * b[c * 4 + k]; }
        r[c * 4 + w] = s;
      }
    }
    return r;
  }

  // 遍历语义树，返回 [id, role, label, state, cx, cy, x, y, w, h, interactive]，坐标为逻辑像素
  List<List<Object>> collect() {
    final res = <List<Object>>[];
    final view = wb.platformDispatcher.implicitView!;
    final dpr = view.devicePixelRatio;
    final vw = view.physicalSize.width / dpr;
    final vh = view.physicalSize.height / dpr;
    final dynamic root = wb.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
    if (root == null) return res;
    double k = 0;
    void visit(dynamic node, List<double> m) {
      if (node.isMergedIntoParent == true) return;
      final dynamic t = node.transform;
      final mm = t == null ? m : mul(m, List<double>.from(t.storage as List<double>));
      final dynamic d = node.getSemanticsData();
      final dynamic f = d.flagsCollection;
      if (f.isHidden == true) return;
      final Rect r = node.rect as Rect;
      final x1 = mm[0] * r.left + mm[4] * r.top + mm[12];
      final y1 = mm[1] * r.left + mm[5] * r.top + mm[13];
      final x2 = mm[0] * r.right + mm[4] * r.bottom + mm[12];
      final y2 = mm[1] * r.right + mm[5] * r.bottom + mm[13];
      if (k == 0) k = (x2 - x1) / vw;
      final gx = x1 / k, gy = y1 / k, gw = (x2 - x1) / k, gh = (y2 - y1) / k;
      final int actions = d.actions as int;
      final toggled = '${f.isToggled}';
      final checked = '${f.isChecked}';
      String role;
      if (f.isTextField == true) { role = 'input'; }
      else if (f.isSlider == true) { role = 'slider'; }
      else if (toggled != 'Tristate.none') { role = 'switch'; }
      else if (checked != 'CheckedState.none') { role = f.isInMutuallyExclusiveGroup == true ? 'radio' : 'check'; }
      else if (f.isLink == true) { role = 'link'; }
      else if (f.isButton == true) { role = 'btn'; }
      else if ((actions & 3) != 0) { role = 'tap'; }
      else if ((actions & 60) != 0) { role = 'scroll'; }
      else if (f.isHeader == true) { role = 'header'; }
      else if (f.isImage == true) { role = 'img'; }
      else { role = 'text'; }
      String label = d.label as String;
      if (label.isEmpty) label = d.tooltip as String;
      final String value = d.value as String;
      if (role == 'input') {
        if (label.isEmpty) label = d.hint as String;
        label = label + '="' + (f.isObscured == true ? '***' : value) + '"';
      } else if (value.isNotEmpty) {
        label = label + ' =' + value;
      }
      label = label.replaceAll(RegExp(r'\s*\n\s*'), ' / ').trim();
      final st = <String>[];
      if ('${f.isSelected}' == 'Tristate.isTrue') st.add('sel');
      if (toggled == 'Tristate.isTrue' || checked == 'CheckedState.isTrue') st.add('on');
      if (toggled == 'Tristate.isFalse' || checked == 'CheckedState.isFalse') st.add('off');
      if ('${f.isEnabled}' == 'Tristate.isFalse') st.add('disabled');
      if ('${f.isFocused}' == 'Tristate.isTrue') st.add('focus');
      final interactive = role != 'text' && role != 'header' && role != 'img';
      final onScreen = x2 > 0 && y2 > 0 && gx < vw && gy < vh && gw > 0 && gh > 0;
      if (onScreen && (interactive || label.isNotEmpty) && !identical(node, root)) {
        res.add(<Object>[node.id as int, role, label, st.join(','), (gx + gw / 2).round(), (gy + gh / 2).round(), gx.round(), gy.round(), gw.round(), gh.round(), interactive]);
      }
      node.visitChildren((dynamic c) { visit(c, mm); return true; });
    }
    visit(root, <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
    // 补漏：BlockSemantics 会让同一边界内先绘制的兄弟节点（如侧栏）整片缺失。
    // 从渲染树补充语义树里没有、且中心点确实能点中的文字和 Tooltip；命中路径上有点击手势的标为 tap。id 记为 -1，按文字重新定位。
    final viewId = wb.platformDispatcher.implicitView!.viewId;
    void scan(Element e) {
      final w = e.widget;
      final ro = e.renderObject;
      String? text;
      if (e is RenderObjectElement && ro is RenderParagraph) text = ro.text.toPlainText();
      else if (w.runtimeType.toString() == 'Tooltip') text = (w as dynamic).message as String?;
      // 图标字体字形落在私有区，没有可读文字，跳过
      if (text != null && text.runes.every((r) => (r >= 0xE000 && r <= 0xF8FF) || r >= 0xF0000)) text = null;
      if (text != null && text.trim().isNotEmpty && ro is RenderBox && ro.attached && ro.hasSize) {
        text = text.replaceAll(RegExp(r'\s*\n\s*'), ' / ').trim();
        final o = ro.localToGlobal(Offset.zero);
        final c = o + ro.size.center(Offset.zero);
        final covered = res.any((s) => (s[2] as String).contains(text!) && Rect.fromLTWH((s[6] as int).toDouble(), (s[7] as int).toDouble(), (s[8] as int).toDouble(), (s[9] as int).toDouble()).inflate(2).contains(c));
        if (!covered && c.dx >= 0 && c.dy >= 0 && c.dx < vw && c.dy < vh) {
          final hr = HitTestResult();
          wb.hitTestInView(hr, c, viewId);
          var hit = false;
          var tappable = false;
          for (final en in hr.path) {
            final Object t = en.target;
            if (!hit && t is RenderObject) {
              RenderObject? r = t;
              while (r != null) { if (identical(r, ro)) { hit = true; break; } r = r.parent; }
            }
            if (t.runtimeType.toString() == 'RenderSemanticsGestureHandler' && (t as dynamic).onTap != null) tappable = true;
          }
          if (hit) res.add(<Object>[-1, tappable ? 'tap' : 'text', text, '', c.dx.round(), c.dy.round(), o.dx.round(), o.dy.round(), ro.size.width.round(), ro.size.height.round(), tappable]);
        }
      }
      e.visitChildren(scan);
    }
    wb.rootElement?.visitChildren(scan);
    return res;
  }

  String line(int n, List<Object> e, bool rect) {
    var s = '@$n ${e[1]} ${e[2]}';
    if ((e[3] as String).isNotEmpty) s += ' [${e[3]}]';
    if (rect) s += ' (${e[6]},${e[7]},${e[8]},${e[9]})';
    return s;
  }

  // 解析目标：@n 先核对快照里的节点是否还在、文字是否一致；文本则在当前语义树里找，可交互且精确匹配优先
  List<Object> resolve(String target) {
    final all = collect();
    if (target.startsWith('@')) {
      final ref = refs[int.tryParse(target.substring(1)) ?? -1];
      if (ref == null) throw 'STALE: 没有 $target，先 snap';
      for (final e in all) {
        if (ref[0] == -1 ? (e[0] == -1 && e[2] == ref[1]) : e[0] == ref[0]) {
          if (e[2] != ref[1]) throw 'STALE: $target 已从「${ref[1]}」变为「${e[2]}」，重新 snap';
          return e;
        }
      }
      throw 'STALE: $target「${ref[1]}」已不在界面上（页面已变化），重新 snap';
    }
    final q = target.toLowerCase();
    final hits = all.where((e) => (e[2] as String).toLowerCase().contains(q)).toList();
    if (hits.isEmpty) throw 'NONE: 找不到「$target」';
    int score(List<Object> e) {
      final l = (e[2] as String).toLowerCase();
      return (e[10] == true ? 0 : 1000) + (l == q ? 0 : 100) + l.length;
    }
    hits.sort((a, b) => score(a) - score(b));
    return hits.first;
  }

  void send(PointerEvent e) => gb.handlePointerEvent(e);

  Future<void> tap(Offset pos, int hold) async {
    final p = ++ptr;
    send(PointerDownEvent(pointer: p, device: touchDev, position: pos));
    await Future<void>.delayed(Duration(milliseconds: hold));
    send(PointerUpEvent(pointer: p, device: touchDev, position: pos));
  }

  Future<String> drag(Offset a, Offset b, int ms) async {
    final p = ++ptr;
    final steps = ms ~/ 16 < 4 ? 4 : ms ~/ 16;
    var last = a;
    send(PointerDownEvent(pointer: p, device: touchDev, position: a));
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(Duration(milliseconds: ms ~/ steps));
      final o = Offset.lerp(a, b, i / steps)!;
      send(PointerMoveEvent(pointer: p, device: touchDev, position: o, delta: o - last));
      last = o;
    }
    send(PointerUpEvent(pointer: p, device: touchDev, position: last));
    return 'ok';
  }

  Offset at(Map<String, String> p) {
    final t = p['target'];
    if (t != null && t.isNotEmpty) {
      final e = resolve(t);
      return Offset((e[4] as int).toDouble(), (e[5] as int).toDouble());
    }
    return Offset(double.parse(p['x']!), double.parse(p['y']!));
  }

  String desc(Map<String, String> p, Offset o) {
    final t = p['target'];
    return t != null && t.isNotEmpty ? '(${o.dx.round()},${o.dy.round()})' : '';
  }

  void reg(String name, Future<String> Function(Map<String, String> p) h) {
    developer.registerExtension('ext.fd.$ver.$name', (String m, Map<String, String> p) async {
      try {
        pump(2500);
        return developer.ServiceExtensionResponse.result('{"r":${js(await h(p))}}');
      } catch (e) {
        return developer.ServiceExtensionResponse.result('{"r":${js('ERR ' + e.toString())}}');
      }
    });
  }

  reg('settle', (p) async { await settle(int.parse(p['ms'] ?? '0')); return 'ok'; });
  reg('info', (p) async {
    final v = wb.platformDispatcher.implicitView!;
    final s = v.physicalSize / v.devicePixelRatio;
    return '窗口 ${s.width.round()}x${s.height.round()} 逻辑像素, dpr ${v.devicePixelRatio}, ${wb.lifecycleState}, framesEnabled ${sched.framesEnabled}, timeDilation $timeDilation, 语义 ${semHandle != null}';
  });
  reg('snap', (p) async {
    await settle(0);
    final all = collect();
    final q = (p['q'] ?? '').toLowerCase();
    final full = p['all'] == '1';
    final rect = p['rect'] == '1';
    refs.clear();
    final out = <String>[];
    var n = 0;
    for (final e in all) {
      if (!full && e[10] != true && e[1] != 'header') continue;
      if (q.isNotEmpty && !(e[2] as String).toLowerCase().contains(q)) continue;
      n++;
      refs[n] = <Object>[e[0], e[2]];
      out.add(line(n, e, rect));
    }
    if (out.isEmpty) return all.isEmpty ? '(语义树为空，稍后重试)' : '(无匹配)';
    return out.join('\n');
  });
  reg('tap', (p) async {
    final o = at(p);
    await tap(o, int.parse(p['hold'] ?? '40'));
    return 'tap ${desc(p, o)}'.trim();
  });
  reg('drag', (p) async {
    final a = at(p);
    final b = a + Offset(double.parse(p['dx']!), double.parse(p['dy']!));
    return drag(a, b, int.parse(p['ms'] ?? '300'));
  });
  reg('hover', (p) async {
    final o = at(p);
    send(PointerHoverEvent(device: mouseDev, kind: PointerDeviceKind.mouse, position: o));
    return 'ok';
  });
  reg('scroll', (p) async {
    final o = at(p);
    send(PointerScrollEvent(device: mouseDev, kind: PointerDeviceKind.mouse, position: o, scrollDelta: Offset(double.parse(p['dx'] ?? '0'), double.parse(p['dy']!))));
    return 'ok';
  });
  reg('type', (p) async {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return 'ERR 没有聚焦的输入框，先 tap 它';
    dynamic st;
    (ctx as Element).visitAncestorElements((a) {
      if (a is StatefulElement && a.state.runtimeType.toString() == 'EditableTextState') st = a.state;
      return st == null;
    });
    if (st == null) return 'ERR 焦点不在输入框上';
    final t = p['text'] ?? '';
    st.updateEditingValue(TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length)));
    if (p['submit'] == '1') st.performAction(st.widget.textInputAction ?? TextInputAction.done);
    return 'ok';
  });
  // 只走 Router 返回分发（无 Router 时退回 Navigator.maybePop）；handlePopRoute 在根路由上会 SystemNavigator.pop 退出应用
  reg('back', (p) async {
    String r = '没有可返回的路由';
    void visit(Element e) {
      final w = e.widget;
      if (w is Router && w.backButtonDispatcher != null) { w.backButtonDispatcher!.invokeCallback(Future<bool>.value(false)); r = 'ok'; return; }
      if (e is StatefulElement && e.state.runtimeType.toString() == 'NavigatorState') { (e.state as dynamic).maybePop(); r = 'ok'; return; }
      e.visitChildren(visit);
    }
    wb.rootElement?.visitChildren(visit);
    return r;
  });
  return 'installed $ver';
})()
