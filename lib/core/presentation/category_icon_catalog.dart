import '../domain/category.dart';

String categoryIconLabel(CategoryIcon icon) => switch (icon) {
  CategoryIcon.wallet => 'Wallet',
  CategoryIcon.bank => 'Bank',
  CategoryIcon.cash => 'Cash',
  CategoryIcon.creditCard => 'Credit card',
  CategoryIcon.receipt => 'Receipt',
  CategoryIcon.tax => 'Tax',
  CategoryIcon.loan => 'Loan',
  CategoryIcon.refund => 'Refund',
  CategoryIcon.transfer => 'Transfer',
  CategoryIcon.budget => 'Budget',
  CategoryIcon.coins => 'Coins',
  CategoryIcon.business => 'Business',
  CategoryIcon.coffee => 'Coffee',
  CategoryIcon.bakery => 'Bakery',
  CategoryIcon.fastFood => 'Fast food',
  CategoryIcon.pizza => 'Pizza',
  CategoryIcon.bar => 'Bar',
  CategoryIcon.iceCream => 'Ice cream',
  CategoryIcon.fruit => 'Fruit',
  CategoryIcon.breakfast => 'Breakfast',
  CategoryIcon.clothing => 'Clothing',
  CategoryIcon.electronics => 'Electronics',
  CategoryIcon.phone => 'Phone',
  CategoryIcon.computer => 'Computer',
  CategoryIcon.furniture => 'Furniture',
  CategoryIcon.beauty => 'Beauty',
  CategoryIcon.jewelry => 'Jewelry',
  CategoryIcon.store => 'Store',
  CategoryIcon.car => 'Car',
  CategoryIcon.fuel => 'Fuel',
  CategoryIcon.train => 'Train',
  CategoryIcon.bike => 'Bike',
  CategoryIcon.taxi => 'Taxi',
  CategoryIcon.parking => 'Parking',
  CategoryIcon.boat => 'Boat',
  CategoryIcon.scooter => 'Scooter',
  CategoryIcon.rent => 'Rent',
  CategoryIcon.electricity => 'Electricity',
  CategoryIcon.water => 'Water',
  CategoryIcon.heating => 'Heating',
  CategoryIcon.internet => 'Internet',
  CategoryIcon.phoneBill => 'Phone bill',
  CategoryIcon.repairs => 'Repairs',
  CategoryIcon.cleaning => 'Cleaning',
  CategoryIcon.garden => 'Garden',
  CategoryIcon.laundry => 'Laundry',
  CategoryIcon.medical => 'Medical',
  CategoryIcon.pharmacy => 'Pharmacy',
  CategoryIcon.dentist => 'Dentist',
  CategoryIcon.fitness => 'Fitness',
  CategoryIcon.spa => 'Spa',
  CategoryIcon.vision => 'Vision',
  CategoryIcon.hospital => 'Hospital',
  CategoryIcon.wellbeing => 'Wellbeing',
  CategoryIcon.music => 'Music',
  CategoryIcon.gaming => 'Gaming',
  CategoryIcon.books => 'Books',
  CategoryIcon.sports => 'Sports',
  CategoryIcon.camera => 'Camera',
  CategoryIcon.art => 'Art',
  CategoryIcon.concert => 'Concert',
  CategoryIcon.hotel => 'Hotel',
  CategoryIcon.beach => 'Beach',
  CategoryIcon.camping => 'Camping',
  CategoryIcon.family => 'Family',
  CategoryIcon.childcare => 'Childcare',
  CategoryIcon.charity => 'Charity',
  CategoryIcon.celebration => 'Celebration',
  CategoryIcon.wedding => 'Wedding',
  CategoryIcon.security => 'Security',
  CategoryIcon.mail => 'Mail',
  CategoryIcon.time => 'Time',
  CategoryIcon.workTools => 'Work tools',
  CategoryIcon.language => 'Language',
  _ => '${icon.name[0].toUpperCase()}${icon.name.substring(1)}',
};

String categoryIconGroup(CategoryIcon icon) => switch (icon) {
  CategoryIcon.wallet ||
  CategoryIcon.bank ||
  CategoryIcon.cash ||
  CategoryIcon.creditCard ||
  CategoryIcon.receipt ||
  CategoryIcon.tax ||
  CategoryIcon.loan ||
  CategoryIcon.refund ||
  CategoryIcon.transfer ||
  CategoryIcon.budget ||
  CategoryIcon.coins ||
  CategoryIcon.business => 'Finance',
  CategoryIcon.coffee ||
  CategoryIcon.bakery ||
  CategoryIcon.fastFood ||
  CategoryIcon.pizza ||
  CategoryIcon.bar ||
  CategoryIcon.iceCream ||
  CategoryIcon.fruit ||
  CategoryIcon.breakfast => 'Food',
  CategoryIcon.clothing ||
  CategoryIcon.electronics ||
  CategoryIcon.phone ||
  CategoryIcon.computer ||
  CategoryIcon.furniture ||
  CategoryIcon.beauty ||
  CategoryIcon.jewelry ||
  CategoryIcon.store => 'Shopping',
  CategoryIcon.car ||
  CategoryIcon.fuel ||
  CategoryIcon.train ||
  CategoryIcon.bike ||
  CategoryIcon.taxi ||
  CategoryIcon.parking ||
  CategoryIcon.boat ||
  CategoryIcon.scooter => 'Transport',
  CategoryIcon.rent ||
  CategoryIcon.electricity ||
  CategoryIcon.water ||
  CategoryIcon.heating ||
  CategoryIcon.internet ||
  CategoryIcon.phoneBill ||
  CategoryIcon.repairs ||
  CategoryIcon.cleaning ||
  CategoryIcon.garden ||
  CategoryIcon.laundry => 'Home & bills',
  CategoryIcon.medical ||
  CategoryIcon.pharmacy ||
  CategoryIcon.dentist ||
  CategoryIcon.fitness ||
  CategoryIcon.spa ||
  CategoryIcon.vision ||
  CategoryIcon.hospital ||
  CategoryIcon.wellbeing => 'Health',
  CategoryIcon.music ||
  CategoryIcon.gaming ||
  CategoryIcon.books ||
  CategoryIcon.sports ||
  CategoryIcon.camera ||
  CategoryIcon.art ||
  CategoryIcon.concert ||
  CategoryIcon.hotel ||
  CategoryIcon.beach ||
  CategoryIcon.camping => 'Leisure',
  CategoryIcon.family ||
  CategoryIcon.childcare ||
  CategoryIcon.charity ||
  CategoryIcon.celebration ||
  CategoryIcon.wedding ||
  CategoryIcon.security ||
  CategoryIcon.mail ||
  CategoryIcon.time ||
  CategoryIcon.workTools ||
  CategoryIcon.language => 'Personal',
  CategoryIcon.general => 'Personal',
  CategoryIcon.groceries || CategoryIcon.dining => 'Food',
  CategoryIcon.transport || CategoryIcon.travel => 'Transport',
  CategoryIcon.home ||
  CategoryIcon.insurance ||
  CategoryIcon.subscriptions => 'Home & bills',
  CategoryIcon.health => 'Health',
  CategoryIcon.shopping => 'Shopping',
  CategoryIcon.entertainment => 'Leisure',
  CategoryIcon.education ||
  CategoryIcon.gifts ||
  CategoryIcon.pets => 'Personal',
  CategoryIcon.salary ||
  CategoryIcon.freelance ||
  CategoryIcon.investments ||
  CategoryIcon.savings => 'Finance',
};
