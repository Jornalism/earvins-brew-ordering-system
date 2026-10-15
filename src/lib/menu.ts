export const categories = ['Coffee', 'Non-coffee', 'Pastries', 'Sandwiches', 'Pasta', 'Meals', 'Add-ons'] as const;
export type Category = typeof categories[number];
export type Product = { id: string; name: string; category: Category; description: string; price: number; image: string; sizes?: {label: string; price: number}[]; sweetness?: boolean; soldOut?: boolean; archived?:boolean };
// Demonstration prices and availability, not a production catalog.
export const products: Product[] = [
  {id:'vietnamese-coffee', name:'Vietnamese Coffee', category:'Coffee', description:'Rich coffee, smooth and bold.', price:120, image:'iced vietnamese latte - grab.png', sizes:[{label:'16oz',price:120},{label:'22oz',price:150}], sweetness:true},
  {id:'iced-latte', name:'Iced Latte', category:'Coffee', description:'Espresso with smooth, creamy milk.', price:120, image:'iced latte.jpg', sizes:[{label:'16oz',price:120},{label:'22oz',price:150}], sweetness:true},
  {id:'iced-matcha', name:'Iced Matcha', category:'Non-coffee', description:'Smooth and earthy.', price:140, image:'Iced matcha latte from Earvin_s Brew.png', sizes:[{label:'16oz',price:140},{label:'22oz',price:150}], sweetness:true},
  {id:'ube-milk', name:'Ube Milk', category:'Non-coffee', description:'Creamy milk with a mellow ube finish.', price:130, image:'ube milk.png', sweetness:true, soldOut:true},
  {id:'croissant', name:'Croissant', category:'Pastries', description:'Buttery and flaky.', price:90, image:'butter croissant.png'},
  {id:'blueberry-muffin', name:'Blueberry Muffin', category:'Pastries', description:'Moist and flavorful.', price:95, image:'blueberry muffin.png'},
  {id:'ham-sandwich', name:'Ham & Cheese Sandwich', category:'Sandwiches', description:'Toasted, warm and satisfying.', price:150, image:'grilled ham and cheese.png'},
  {id:'tuna-sandwich', name:'Tuna Sandwich', category:'Sandwiches', description:'A hearty café favorite.', price:150, image:'tuna sandwich.png'},
];
export const statuses = ['Pending Payment','Preparing','Ready for Pickup','Completed','Cancelled'] as const;
export type OrderStatus = typeof statuses[number];
export const money = (value:number) => new Intl.NumberFormat('en-PH',{style:'currency',currency:'PHP'}).format(value);
