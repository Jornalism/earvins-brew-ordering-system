'use client';
import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import type { OrderStatus } from '@/lib/menu';
export type CartItem = {id:string; productId:string; name:string; size:string; sweetness:string; note:string; quantity:number; price:number};
export type Order = {id:string; queue:string; table:number; items:CartItem[]; status:OrderStatus};
type State = {cart:CartItem[]; orders:Order[]};
type Store = State & {ready:boolean; saveItem:(item:CartItem)=>void; removeItem:(id:string)=>void; placeOrder:()=>string|null};
const Context = createContext<Store|null>(null);
const key = 'earvins-customer-demo-v1';
export function OrderProvider({children}:{children:ReactNode}) {
 const [state,setState]=useState<State>({cart:[],orders:[]});
 const [ready,setReady]=useState(false);
 useEffect(()=>{let next:State={cart:[],orders:[]}; try{const raw=JSON.parse(localStorage.getItem(key)||'null'); if(raw && Array.isArray(raw.cart) && Array.isArray(raw.orders)) next=raw;}catch{}; queueMicrotask(()=>{setState(next);setReady(true)});},[]);
 useEffect(()=>{if(ready){try{localStorage.setItem(key,JSON.stringify(state));}catch{ /* Ordering still works in memory when storage is unavailable. */ }}},[state,ready]);
 const saveItem=(item:CartItem)=>setState(s=>({...s,cart:s.cart.some(x=>x.id===item.id)?s.cart.map(x=>x.id===item.id?item:x):[...s.cart,item]}));
 const removeItem=(id:string)=>setState(s=>({...s,cart:s.cart.filter(x=>x.id!==id)}));
 const placeOrder=()=>{if(!state.cart.length)return null;const id=crypto.randomUUID();const order:Order={id,queue:String(state.orders.length+1).padStart(3,'0'),table:5,items:state.cart,status:'Pending Payment'};setState(s=>({cart:[],orders:[...s.orders,order]}));return id;};
 return <Context.Provider value={{...state,ready,saveItem,removeItem,placeOrder}}>{children}</Context.Provider>;
}
export function useOrder(){const value=useContext(Context);if(!value)throw new Error('OrderProvider missing');return value;}
