'use client';
import {useEffect,useState} from 'react';
import Image from 'next/image';
import QRCode from 'qrcode';
import {useCatalog,type CafeTable} from '@/components/catalog-provider';
export function TableCard({table}:{table:CafeTable}){
 const {saveTable}=useCatalog();const [qr,setQr]=useState('');const [url,setUrl]=useState('');const [error,setError]=useState('');
 useEffect(()=>{let disposed=false;const url=new URL(`/menu?table=${table.number}`,window.location.origin).href;QRCode.toDataURL(url,{width:512,margin:4,errorCorrectionLevel:'M'}).then(data=>{if(!disposed){setQr(data);setUrl(url)}}).catch(()=>{if(!disposed)setError('Could not generate QR code.')});return()=>{disposed=true}},[table.number]);
 function print(){const target=document.querySelector('[data-table="'+table.number+'"]');target?.classList.add('print-target');document.body.dataset.printTable=String(table.number);const clear=()=>{delete document.body.dataset.printTable;target?.classList.remove('print-target');window.removeEventListener('afterprint',clear)};window.addEventListener('afterprint',clear);window.print()}
 return <article className="table-card" data-table={table.number} aria-label={`Table ${table.number}`}><div><h2>Table {table.number}</h2><p>{table.seats} seats</p><p>{table.location}</p>{!table.active&&<strong className="danger">Inactive</strong>}</div><div className="qr-preview">{qr?<Image src={qr} alt={`QR code for Table ${table.number}`} width={128} height={128} unoptimized/>:<p>{error||'Generating QR…'}</p>}</div><div className="table-actions">{qr&&table.active&&<><a className="admin-button secondary" download={`earvins-table-${table.number}.png`} href={qr}>Download QR</a><button className="admin-button secondary" onClick={print}>Print QR</button></>}<button className="admin-button secondary" onClick={()=>{if(!table.active||window.confirm(`Deactivate Table ${table.number}?`))saveTable({...table,active:!table.active})}}>{table.active?'Deactivate':'Reactivate'}</button></div><p className="table-url">{table.active?<a href={url}>{url}</a>:'This table is unavailable for new orders.'}</p><p className="print-only">Local demo QR · Pay and collect at the counter.</p></article>;
}
