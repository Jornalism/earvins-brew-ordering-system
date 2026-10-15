'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
export function useLocalDemo<T>(key:string,initial:T,valid:(v:unknown)=>v is T){
 const [state,setState]=useState(initial);const current=useRef(initial);const [ready,setReady]=useState(false);const [storageError,setStorageError]=useState('');
 useEffect(()=>{const read=(raw:string|null)=>{try{const v:unknown=JSON.parse(raw||'null');return valid(v)?v:initial}catch{return initial}};let value=initial;try{value=read(localStorage.getItem(key))}catch{}current.current=value;queueMicrotask(()=>{setState(value);setReady(true)});const sync=(e:StorageEvent)=>{if(e.key===key){const next=read(e.newValue);current.current=next;setState(next)}};window.addEventListener('storage',sync);return()=>window.removeEventListener('storage',sync)},[key,initial,valid]);
 const update=useCallback((change:(old:T)=>T)=>{const next=change(current.current);current.current=next;setState(next);try{localStorage.setItem(key,JSON.stringify(next));setStorageError('')}catch{setStorageError('Browser storage is full or unavailable. Changes work in this tab but may not survive a reload. Try a smaller image.')}return next},[key]);
 return {state,ready,update,storageError};
}
