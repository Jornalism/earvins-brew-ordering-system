'use client';
import {createContext,useContext,type ReactNode} from 'react';
import type {OrderStatus} from '@/lib/menu';
import {useLocalDemo} from '@/lib/use-local-demo';
import {useCatalog} from './catalog-provider';
export type CartItem={id:string;productId:string;name:string;size:string;sweetness:string;note:string;quantity:number;price:number};
export type Order={id:string;queue:string;table:number;items:CartItem[];status:OrderStatus;createdAt?:string};
type State={cart:CartItem[];orders:Order[];demoLoaded?:boolean;table?:number};
const initial:State={cart:[],orders:[]};
const valid=(v:unknown):v is State=>!!v&&typeof v==='object'&&Array.isArray((v as State).cart)&&Array.isArray((v as State).orders);
type Store=State & {ready:boolean;storageError:string;checkoutError:string;saveItem:(item:CartItem)=>void;removeItem:(id:string)=>void;placeOrder:()=>string|null;changeStatus:(id:string,status:OrderStatus)=>void;loadExamples:()=>void};
const Context=createContext<Store|null>(null);
const transitions:Record<OrderStatus,OrderStatus[]>={'Pending Payment':['Preparing','Cancelled'],Preparing:['Ready for Pickup','Cancelled'],'Ready for Pickup':['Completed','Cancelled'],Completed:[],Cancelled:[]};
export function OrderProvider({children}:{children:ReactNode}){
 const {state,ready,update,storageError}=useLocalDemo('earvins-customer-demo-v1',initial,valid);
 const catalog=useCatalog();
 const unavailable=state.cart.some(item=>{const p=catalog.products.find(p=>p.id===item.productId);return !p||p.archived||p.soldOut});
 const activeTable=state.table??catalog.table;
 const checkoutError=!catalog.tables.some(t=>t.number===activeTable&&t.active)?'This table is inactive. Please speak to counter staff.':unavailable?'An item in your cart is unavailable. Remove it before placing your order.':'';
 const saveItem=(item:CartItem)=>update(s=>({...s,table:catalog.table,cart:s.cart.some(x=>x.id===item.id)?s.cart.map(x=>x.id===item.id?item:x):[...s.cart,item]}));
 const removeItem=(id:string)=>update(s=>({...s,cart:s.cart.filter(x=>x.id!==id)}));
 const placeOrder=()=>{if(!state.cart.length||checkoutError||!ready||!catalog.ready)return null;const id=crypto.randomUUID();update(s=>{const order:Order={id,queue:String(s.orders.length+1).padStart(3,'0'),table:s.table??catalog.table,items:s.cart,status:'Pending Payment',createdAt:new Date().toISOString()};return {...s,cart:[],orders:[...s.orders,order]}});return id;};
 const changeStatus=(id:string,status:OrderStatus)=>update(s=>({...s,orders:s.orders.map(o=>o.id===id&&transitions[o.status].includes(status)?{...o,status}:o)}));
 const loadExamples=()=>update(s=>{if(s.demoLoaded)return s;const sample:OrderStatus[]=['Pending Payment','Preparing','Ready for Pickup','Completed','Cancelled'];return {...s,demoLoaded:true,orders:[...s.orders,...sample.map((status,i)=>({id:crypto.randomUUID(),queue:String(s.orders.length+i+1).padStart(3,'0'),table:i+1,status,createdAt:new Date(Date.now()-i*3600000).toISOString(),items:[{id:crypto.randomUUID(),productId:'vietnamese-coffee',name:'Vietnamese Coffee',size:'16oz',sweetness:'Less Sweet',note:'More ice',quantity:1,price:120},{id:crypto.randomUUID(),productId:'croissant',name:'Croissant',size:'',sweetness:'',note:'',quantity:1,price:90}]}))]}});
 return <Context.Provider value={{...state,ready:ready&&catalog.ready,storageError,checkoutError,saveItem,removeItem,placeOrder,changeStatus,loadExamples}}>{children}</Context.Provider>;
}
export function useOrder(){const v=useContext(Context);if(!v)throw new Error('OrderProvider missing');return v;}
