'use client';
import {createContext,useContext,useState,useEffect,useCallback,type ReactNode} from 'react';
import {products as originals,type Product} from '@/lib/menu';
import {useLocalDemo} from '@/lib/use-local-demo';
export type CafeTable={number:number;seats:number;location:string;active:boolean};
type Catalog={products:Product[];tables:CafeTable[]};
const initial:Catalog={products:originals,tables:[1,2,3,4,5].map(number=>({number,seats:number%2?4:2,location:number<4?'Indoor':'Outdoor',active:true}))};
const valid=(v:unknown):v is Catalog=>!!v&&typeof v==='object'&&Array.isArray((v as Catalog).products)&&Array.isArray((v as Catalog).tables);
type Store=Catalog & {ready:boolean;storageError:string;table:number;tableActive:boolean;selectTable:(n:number)=>void;updateProduct:(p:Product)=>void;saveTable:(t:CafeTable)=>void};
const Context=createContext<Store|null>(null);
export function CatalogProvider({children}:{children:ReactNode}){const {state,ready,update,storageError}=useLocalDemo('earvins-catalog-demo-v1',initial,valid);const [table,setTable]=useState(5);useEffect(()=>{let saved=5;try{saved=Number(new URLSearchParams(window.location.search).get('table')||sessionStorage.getItem('earvins-demo-table')||5)}catch{}if(Number.isInteger(saved)&&saved>0)queueMicrotask(()=>setTable(saved))},[]);const selectTable=useCallback((number:number)=>{setTable(number);try{sessionStorage.setItem('earvins-demo-table',String(number))}catch{}},[]);const updateProduct=(p:Product)=>update(s=>({...s,products:s.products.map(x=>x.id===p.id?p:x)}));const saveTable=(t:CafeTable)=>update(s=>({...s,tables:s.tables.some(x=>x.number===t.number)?s.tables.map(x=>x.number===t.number?t:x):[...s.tables,t]}));return <Context.Provider value={{...state,ready,storageError,table,tableActive:state.tables.some(t=>t.number===table&&t.active),selectTable,updateProduct,saveTable}}>{children}</Context.Provider>}
export function useCatalog(){const v=useContext(Context);if(!v)throw new Error('CatalogProvider missing');return v;}
export const productImage=(p:Product)=>p.image.startsWith('data:image/')?p.image:`/images/products/${p.image}`;
