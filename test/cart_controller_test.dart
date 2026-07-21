import 'package:cashinator/data/models/product.dart';
import 'package:cashinator/state/cart_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const croissant = Product(id: 1, name: 'Croissant', price: 3000, active: true);
const muffin = Product(id: 2, name: 'Muffin', price: 2000, active: true);

void main() {
  late CartController cart;

  setUp(() => cart = CartController());

  test('starts empty', () {
    expect(cart.isEmpty, isTrue);
    expect(cart.total, 0);
    expect(cart.itemCount, 0);
  });

  test('repeated taps on one product increment instead of adding lines', () {
    cart.add(croissant);
    cart.add(croissant);
    cart.add(croissant);

    expect(cart.lineCount, 1, reason: 'one line, not three');
    expect(cart.itemCount, 3);
    expect(cart.total, 9000);
  });

  test('different products get their own lines', () {
    cart.add(croissant);
    cart.add(muffin);

    expect(cart.lineCount, 2);
    expect(cart.total, 5000);
  });

  test('decrement removes the line when it reaches zero', () {
    cart.add(croissant);
    cart.add(croissant);

    cart.decrement(croissant);
    expect(cart.qtyOf(croissant), 1);

    cart.decrement(croissant);
    expect(cart.qtyOf(croissant), 0);
    expect(cart.isEmpty, isTrue);
  });

  test('decrementing something absent is a no-op', () {
    cart.decrement(croissant);
    expect(cart.isEmpty, isTrue);
  });

  test('setQty of zero or less removes the line', () {
    cart.add(croissant);
    cart.setQty(croissant, 0);
    expect(cart.isEmpty, isTrue);
  });

  test('setQty caps a runaway entry', () {
    cart.add(croissant);
    cart.setQty(croissant, 100000);
    expect(cart.qtyOf(croissant), 999);
  });

  test('toDraftLines copies the price at cart time', () {
    cart.add(croissant);
    cart.add(croissant);

    final drafts = cart.toDraftLines();
    expect(drafts, hasLength(1));
    expect(drafts.single.qty, 2);
    expect(drafts.single.unitPrice, 3000);
    expect(drafts.single.productName, 'Croissant');
    expect(drafts.single.lineTotal, 6000);
  });

  test('clear empties the cart', () {
    cart.add(croissant);
    cart.add(muffin);
    cart.clear();

    expect(cart.isEmpty, isTrue);
    expect(cart.total, 0);
  });

  test('notifies listeners on change', () {
    var notifications = 0;
    cart.addListener(() => notifications++);

    cart.add(croissant);
    cart.decrement(croissant);
    cart.clear(); // already empty — must not notify

    expect(notifications, 2);
  });
}
