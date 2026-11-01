import '../domain/category.dart';

String categoryIconLabel(CategoryIcon icon) => switch (icon) {
  CategoryIcon.netflix => 'Netflix',
  CategoryIcon.youtube => 'YouTube',
  CategoryIcon.spotify => 'Spotify',
  CategoryIcon.apple => 'Apple',
  CategoryIcon.google => 'Google',
  CategoryIcon.tiktok => 'TikTok',
  CategoryIcon.instagram => 'Instagram',
  CategoryIcon.facebook => 'Facebook',
  CategoryIcon.xTwitter => 'X / Twitter',
  CategoryIcon.twitch => 'Twitch',
  CategoryIcon.linkedin => 'LinkedIn',
  CategoryIcon.github => 'GitHub',
  CategoryIcon.amazon => 'Amazon',
  CategoryIcon.discord => 'Discord',
  CategoryIcon.uber => 'Uber',
  CategoryIcon.airbnb => 'Airbnb',
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

const categoryIconGroups = [
  'Finance',
  'Shopping',
  'Food and Lifestyle',
  'Transport and Travel',
  'Home and Family',
  'Health and Work',
  'Utilities and Devices',
  'Brands and Streaming',
  'Misc',
];

String categoryIconGroup(CategoryIcon icon) => switch (icon) {
  CategoryIcon.salary ||
  CategoryIcon.investments ||
  CategoryIcon.savings ||
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
  CategoryIcon.coins => 'Finance',
  CategoryIcon.shopping ||
  CategoryIcon.groceries ||
  CategoryIcon.clothing ||
  CategoryIcon.beauty ||
  CategoryIcon.jewelry ||
  CategoryIcon.store ||
  CategoryIcon.gifts => 'Shopping',
  CategoryIcon.dining ||
  CategoryIcon.coffee ||
  CategoryIcon.bakery ||
  CategoryIcon.fastFood ||
  CategoryIcon.pizza ||
  CategoryIcon.bar ||
  CategoryIcon.iceCream ||
  CategoryIcon.fruit ||
  CategoryIcon.breakfast ||
  CategoryIcon.entertainment ||
  CategoryIcon.music ||
  CategoryIcon.gaming ||
  CategoryIcon.sports ||
  CategoryIcon.camera ||
  CategoryIcon.art ||
  CategoryIcon.concert ||
  CategoryIcon.celebration => 'Food and Lifestyle',
  CategoryIcon.transport ||
  CategoryIcon.travel ||
  CategoryIcon.car ||
  CategoryIcon.fuel ||
  CategoryIcon.train ||
  CategoryIcon.bike ||
  CategoryIcon.taxi ||
  CategoryIcon.parking ||
  CategoryIcon.boat ||
  CategoryIcon.scooter ||
  CategoryIcon.hotel ||
  CategoryIcon.beach ||
  CategoryIcon.camping => 'Transport and Travel',
  CategoryIcon.home ||
  CategoryIcon.rent ||
  CategoryIcon.furniture ||
  CategoryIcon.pets ||
  CategoryIcon.education ||
  CategoryIcon.family ||
  CategoryIcon.childcare ||
  CategoryIcon.garden ||
  CategoryIcon.cleaning ||
  CategoryIcon.wedding => 'Home and Family',
  CategoryIcon.health ||
  CategoryIcon.medical ||
  CategoryIcon.pharmacy ||
  CategoryIcon.dentist ||
  CategoryIcon.fitness ||
  CategoryIcon.spa ||
  CategoryIcon.vision ||
  CategoryIcon.hospital ||
  CategoryIcon.wellbeing ||
  CategoryIcon.freelance ||
  CategoryIcon.business ||
  CategoryIcon.repairs ||
  CategoryIcon.workTools ||
  CategoryIcon.charity => 'Health and Work',
  CategoryIcon.electronics ||
  CategoryIcon.phone ||
  CategoryIcon.computer ||
  CategoryIcon.electricity ||
  CategoryIcon.water ||
  CategoryIcon.heating ||
  CategoryIcon.internet ||
  CategoryIcon.phoneBill ||
  CategoryIcon.laundry ||
  CategoryIcon.books ||
  CategoryIcon.subscriptions => 'Utilities and Devices',
  CategoryIcon.netflix ||
  CategoryIcon.youtube ||
  CategoryIcon.spotify ||
  CategoryIcon.apple ||
  CategoryIcon.google ||
  CategoryIcon.tiktok ||
  CategoryIcon.instagram ||
  CategoryIcon.facebook ||
  CategoryIcon.xTwitter ||
  CategoryIcon.twitch ||
  CategoryIcon.linkedin ||
  CategoryIcon.github ||
  CategoryIcon.amazon ||
  CategoryIcon.discord ||
  CategoryIcon.uber ||
  CategoryIcon.airbnb => 'Brands and Streaming',
  _ => 'Misc',
};
