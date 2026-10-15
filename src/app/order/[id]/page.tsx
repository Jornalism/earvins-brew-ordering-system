import {OrderView} from '@/components/order-view';
export default async function Confirmation({params}:{params:Promise<{id:string}>}){const {id}=await params;return <OrderView id={id}/>}
